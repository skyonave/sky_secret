#include "secret_fill.h"

#include <UIAutomation.h>
#include <UIAutomationCore.h>
#include <oleacc.h>
#include <wrl/client.h>
#include <cstring>

using Microsoft::WRL::ComPtr;

SecretField ClassifyAccessibleSecretField(LONG role, LONG state) {
  if (role != ROLE_SYSTEM_TEXT ||
      (state & (STATE_SYSTEM_READONLY | STATE_SYSTEM_UNAVAILABLE | STATE_SYSTEM_INVISIBLE | STATE_SYSTEM_OFFSCREEN))) {
    return SecretField::unknown;
  }
  return (state & STATE_SYSTEM_PROTECTED) ? SecretField::password : SecretField::username;
}

namespace {
std::vector<LONG> AccessibleRuntimeIdentity(IUnknown* object, LONG child) {
  ComPtr<IAccessibleEx> extended;
  if (FAILED(object->QueryInterface(IID_PPV_ARGS(&extended)))) return {};
  if (child != CHILDID_SELF) {
    ComPtr<IAccessibleEx> child_object;
    if (FAILED(extended->GetObjectForChild(child, &child_object)) || !child_object) return {};
    extended = std::move(child_object);
  }
  SAFEARRAY* array = nullptr;
  const auto status = extended->GetRuntimeId(&array);
  std::vector<LONG> result;
  LONG lower = 0;
  LONG upper = -1;
  VARTYPE type = VT_EMPTY;
  if (status == S_OK && array && SafeArrayGetDim(array) == 1 &&
      SUCCEEDED(SafeArrayGetVartype(array, &type)) && type == VT_I4 &&
      SUCCEEDED(SafeArrayGetLBound(array, 1, &lower)) && SUCCEEDED(SafeArrayGetUBound(array, 1, &upper))) {
    const auto count = static_cast<int64_t>(upper) - lower + 1;
    LONG* data = nullptr;
    if (count > 0 && count <= 64 && SUCCEEDED(SafeArrayAccessData(array, reinterpret_cast<void**>(&data)))) {
      result.assign(data, data + count);
      SafeArrayUnaccessData(array);
    }
  }
  if (array) SafeArrayDestroy(array);
  return result;
}

bool SameIdentityString(IUnknown* left, LONG left_child, IUnknown* right, LONG right_child) {
  ComPtr<IAccIdentity> left_identity;
  ComPtr<IAccIdentity> right_identity;
  if (FAILED(left->QueryInterface(IID_PPV_ARGS(&left_identity))) ||
      FAILED(right->QueryInterface(IID_PPV_ARGS(&right_identity)))) return false;
  BYTE* left_bytes = nullptr;
  BYTE* right_bytes = nullptr;
  DWORD left_size = 0;
  DWORD right_size = 0;
  const auto left_status = left_identity->GetIdentityString(left_child, &left_bytes, &left_size);
  const auto right_status = right_identity->GetIdentityString(right_child, &right_bytes, &right_size);
  const bool same = left_status == S_OK && right_status == S_OK && left_bytes && right_bytes &&
      left_size > 0 && left_size <= 4096 && left_size == right_size &&
      std::memcmp(left_bytes, right_bytes, left_size) == 0;
  CoTaskMemFree(left_bytes);
  CoTaskMemFree(right_bytes);
  return same;
}
}

bool SameAccessibleIdentity(IUnknown* left, LONG left_child, IUnknown* right, LONG right_child) {
  if (!left || !right) return false;
  if (left == right && left_child == right_child) return true;
  if (SameIdentityString(left, left_child, right, right_child)) return true;
  const auto left_runtime = AccessibleRuntimeIdentity(left, left_child);
  const auto right_runtime = AccessibleRuntimeIdentity(right, right_child);
  return !left_runtime.empty() && left_runtime == right_runtime;
}

namespace {
bool WindowMatches(HWND target, POINT point) {
  DWORD process = 0;
  GetWindowThreadProcessId(target, &process);
  return process && process != GetCurrentProcessId() && IsWindowVisible(target) &&
      GetAncestor(WindowFromPoint(point), GA_ROOT) == target;
}

bool BooleanProperty(IUIAutomationElement* element, PROPERTYID property, bool* result) {
  VARIANT value;
  VariantInit(&value);
  const auto status = element->GetCurrentPropertyValueEx(property, TRUE, &value);
  const bool valid = SUCCEEDED(status) && value.vt == VT_BOOL;
  if (valid) *result = value.boolVal == VARIANT_TRUE;
  VariantClear(&value);
  return valid;
}

bool Contains(RECT bounds, POINT point) {
  return bounds.right > bounds.left && bounds.bottom > bounds.top && PtInRect(&bounds, point);
}

class AutomationTarget final : public SecretFillTarget {
 public:
  ComPtr<IUIAutomation> automation;
  ComPtr<IUIAutomationElement> element;
  ComPtr<IUIAutomationValuePattern> value;
  ComPtr<IUIAutomationLegacyIAccessiblePattern> legacy;
  SecretField field = SecretField::unknown;
  HWND window = nullptr;
  POINT point{};

  SecretField Field() const override { return field; }
  std::unique_ptr<SecretFillTarget> Partner() const override;
  bool Same(const SecretFillTarget& other) const override {
    const auto* current = dynamic_cast<const AutomationTarget*>(&other);
    BOOL same = FALSE;
    return current && window == current->window &&
        SUCCEEDED(automation->CompareElements(element.Get(), current->element.Get(), &same)) && same;
  }
  HRESULT SetValue(BSTR text) override {
    if (!WindowMatches(window, point)) return E_ABORT;
    return value ? value->SetValue(text) : legacy->SetValue(text);
  }
};

bool BelongsToWindow(IUIAutomationElement* element, IUIAutomationTreeWalker* walker, HWND window) {
  ComPtr<IUIAutomationElement> current = element;
  for (int depth = 0; current && depth < 16; ++depth) {
    UIA_HWND native = nullptr;
    if (SUCCEEDED(current->get_CurrentNativeWindowHandle(&native)) && native) {
      return GetAncestor(reinterpret_cast<HWND>(native), GA_ROOT) == window;
    }
    ComPtr<IUIAutomationElement> parent;
    if (FAILED(walker->GetParentElement(current.Get(), &parent))) return false;
    current = std::move(parent);
  }
  return false;
}

std::unique_ptr<SecretFillTarget> AutomationAtPoint(IUIAutomation* automation, POINT point, HWND window) {
  if (!automation) return nullptr;
  auto target = std::make_unique<AutomationTarget>();
  target->automation = automation;
  ComPtr<IUIAutomationTreeWalker> walker;
  if (FAILED(target->automation->get_RawViewWalker(&walker)) || !walker ||
      FAILED(target->automation->ElementFromPoint(point, &target->element)) || !target->element) return nullptr;
  bool editable = false;
  for (int depth = 0; depth < 5 && target->element; ++depth) {
    CONTROLTYPEID type = 0;
    RECT bounds{};
    if (FAILED(target->element->get_CurrentBoundingRectangle(&bounds)) || !Contains(bounds, point) ||
        FAILED(target->element->get_CurrentControlType(&type))) return nullptr;
    if (type == UIA_EditControlTypeId) {
      editable = true;
      break;
    }
    if (type != UIA_TextControlTypeId && type != UIA_CustomControlTypeId && type != UIA_PaneControlTypeId) break;
    ComPtr<IUIAutomationElement> parent;
    if (FAILED(walker->GetParentElement(target->element.Get(), &parent))) return nullptr;
    target->element = std::move(parent);
  }
  bool enabled = false;
  bool password = false;
  bool offscreen = true;
  if (!editable || !BooleanProperty(target->element.Get(), UIA_IsEnabledPropertyId, &enabled) || !enabled ||
      !BooleanProperty(target->element.Get(), UIA_IsOffscreenPropertyId, &offscreen) || offscreen ||
      !BooleanProperty(target->element.Get(), UIA_IsPasswordPropertyId, &password) ||
      !BelongsToWindow(target->element.Get(), walker.Get(), window)) return nullptr;
  if (SUCCEEDED(target->element->GetCurrentPatternAs(UIA_ValuePatternId, IID_PPV_ARGS(&target->value))) && target->value) {
    BOOL readonly = TRUE;
    if (FAILED(target->value->get_CurrentIsReadOnly(&readonly)) || readonly) return nullptr;
  } else {
    DWORD state = 0;
    DWORD role = 0;
    if (FAILED(target->element->GetCurrentPatternAs(UIA_LegacyIAccessiblePatternId,
                                                   IID_PPV_ARGS(&target->legacy))) || !target->legacy ||
        FAILED(target->legacy->get_CurrentRole(&role)) ||
        FAILED(target->legacy->get_CurrentState(&state)) ||
        ClassifyAccessibleSecretField(role, state) !=
            (password ? SecretField::password : SecretField::username)) return nullptr;
  }
  target->field = password ? SecretField::password : SecretField::username;
  target->window = window;
  target->point = point;
  return WindowMatches(window, point) ? std::move(target) : nullptr;
}

class AccessibleTarget final : public SecretFillTarget {
 public:
  ComPtr<IUIAutomation> automation;
  ComPtr<IAccessible> accessible;
  ComPtr<IUnknown> identity;
  LONG child = CHILDID_SELF;
  SecretField field = SecretField::unknown;
  HWND window = nullptr;
  POINT point{};

  SecretField Field() const override { return field; }
  std::unique_ptr<SecretFillTarget> Partner() const override;
  bool Same(const SecretFillTarget& other) const override {
    const auto* current = dynamic_cast<const AccessibleTarget*>(&other);
    if (!current || window != current->window) return false;
    if (SameAccessibleIdentity(identity.Get(), child, current->identity.Get(), current->child)) return true;
    if (!automation) return false;
    ComPtr<IUIAutomationElement> left;
    ComPtr<IUIAutomationElement> right;
    BOOL same = FALSE;
    return SUCCEEDED(automation->ElementFromIAccessible(accessible.Get(), child, &left)) && left &&
        SUCCEEDED(automation->ElementFromIAccessible(current->accessible.Get(), current->child, &right)) && right &&
        SUCCEEDED(automation->CompareElements(left.Get(), right.Get(), &same)) && same;
  }
  HRESULT SetValue(BSTR text) override {
    if (!WindowMatches(window, point)) return E_ABORT;
    VARIANT id;
    VariantInit(&id);
    id.vt = VT_I4;
    id.lVal = child;
    return accessible->put_accValue(id, text);
  }
};

std::unique_ptr<SecretFillTarget> AccessibleAtPoint(IUIAutomation* automation, POINT point, HWND window) {
  auto target = std::make_unique<AccessibleTarget>();
  target->automation = automation;
  VARIANT id;
  VariantInit(&id);
  const auto found = AccessibleObjectFromPoint(point, &target->accessible, &id);
  if (FAILED(found) || !target->accessible || id.vt != VT_I4) {
    VariantClear(&id);
    return nullptr;
  }
  VARIANT role;
  VARIANT state;
  VariantInit(&role);
  VariantInit(&state);
  const auto role_status = target->accessible->get_accRole(id, &role);
  const auto state_status = target->accessible->get_accState(id, &state);
  const auto field = SUCCEEDED(role_status) && role.vt == VT_I4 && SUCCEEDED(state_status) && state.vt == VT_I4
      ? ClassifyAccessibleSecretField(role.lVal, state.lVal) : SecretField::unknown;
  VariantClear(&role);
  VariantClear(&state);
  if (field == SecretField::unknown) return nullptr;
  HWND native = nullptr;
  LONG left = 0, top = 0, width = 0, height = 0;
  if (FAILED(WindowFromAccessibleObject(target->accessible.Get(), &native)) || !native ||
      GetAncestor(native, GA_ROOT) != window ||
      FAILED(target->accessible->accLocation(&left, &top, &width, &height, id)) ||
      width <= 0 || height <= 0 || point.x < left || point.y < top ||
      static_cast<int64_t>(point.x) >= static_cast<int64_t>(left) + width ||
      static_cast<int64_t>(point.y) >= static_cast<int64_t>(top) + height ||
      FAILED(target->accessible.As(&target->identity))) return nullptr;
  target->child = id.lVal;
  target->field = field;
  target->window = window;
  target->point = point;
  return WindowMatches(window, point) ? std::move(target) : nullptr;
}

POINT Center(RECT bounds) {
  return {static_cast<LONG>((static_cast<int64_t>(bounds.left) + bounds.right) / 2),
          static_cast<LONG>((static_cast<int64_t>(bounds.top) + bounds.bottom) / 2)};
}

bool AutomationScope(IUIAutomationElement* element, bool* boundary) {
  bool dialog = false;
  BooleanProperty(element, UIA_IsDialogPropertyId, &dialog);
  VARIANT role;
  VariantInit(&role);
  element->GetCurrentPropertyValueEx(UIA_AriaRolePropertyId, TRUE, &role);
  const bool form = role.vt == VT_BSTR && role.bstrVal &&
      (wcscmp(role.bstrVal, L"form") == 0 || wcscmp(role.bstrVal, L"dialog") == 0 ||
       wcscmp(role.bstrVal, L"alertdialog") == 0);
  VariantClear(&role);
  *boundary = dialog || form;
  CONTROLTYPEID type = 0;
  element->get_CurrentControlType(&type);
  return *boundary || type == UIA_GroupControlTypeId;
}

std::unique_ptr<SecretFillTarget> AutomationTarget::Partner() const {
  ComPtr<IUIAutomationTreeWalker> walker;
  if (FAILED(automation->get_RawViewWalker(&walker)) || !walker) return nullptr;
  ComPtr<IUIAutomationCondition> edits;
  VARIANT type;
  VariantInit(&type);
  type.vt = VT_I4;
  type.lVal = UIA_EditControlTypeId;
  if (FAILED(automation->CreatePropertyCondition(UIA_ControlTypePropertyId, type, &edits))) return nullptr;
  ComPtr<IUIAutomationElement> parent = element;
  const auto deadline = GetTickCount64() + 400;
  for (int depth = 0; depth < 8 && GetTickCount64() < deadline; ++depth) {
    ComPtr<IUIAutomationElement> next;
    if (FAILED(walker->GetParentElement(parent.Get(), &next)) || !next) return nullptr;
    parent = std::move(next);
    if (!BelongsToWindow(parent.Get(), walker.Get(), window)) return nullptr;
    bool boundary = false;
    if (!AutomationScope(parent.Get(), &boundary)) {
      CONTROLTYPEID parent_type = 0;
      if (FAILED(parent->get_CurrentControlType(&parent_type)) || parent_type == UIA_DocumentControlTypeId ||
          parent_type == UIA_WindowControlTypeId) return nullptr;
      continue;
    }
    ComPtr<IUIAutomationElementArray> fields;
    int count = 0;
    if (FAILED(parent->FindAll(TreeScope_Descendants, edits.Get(), &fields)) || !fields ||
        FAILED(fields->get_Length(&count))) return nullptr;
    if (count < 2 && !boundary) continue;
    if (count != 2 || GetTickCount64() >= deadline) return nullptr;
    std::vector<std::unique_ptr<SecretFillTarget>> candidates;
    for (int index = 0; index < count; ++index) {
      ComPtr<IUIAutomationElement> candidate;
      RECT bounds{};
      if (FAILED(fields->GetElement(index, &candidate)) || !candidate ||
          FAILED(candidate->get_CurrentBoundingRectangle(&bounds))) return nullptr;
      const auto center = Center(bounds);
      auto resolved = AutomationAtPoint(automation.Get(), center, window);
      const auto* native = dynamic_cast<const AutomationTarget*>(resolved.get());
      BOOL same = FALSE;
      if (!native || FAILED(automation->CompareElements(candidate.Get(), native->element.Get(), &same)) || !same) {
        return nullptr;
      }
      candidates.push_back(std::move(resolved));
    }
    return GetTickCount64() < deadline ? SelectSecretPartner(*this, std::move(candidates)) : nullptr;
  }
  return nullptr;
}

bool AccessibleRole(IAccessible* object, LONG child, LONG* role) {
  VARIANT id;
  VariantInit(&id);
  id.vt = VT_I4;
  id.lVal = child;
  VARIANT value;
  VariantInit(&value);
  const auto result = object->get_accRole(id, &value);
  const bool valid = result == S_OK && value.vt == VT_I4;
  if (valid) *role = value.lVal;
  VariantClear(&value);
  return valid;
}

struct AccessiblePairScan {
  IUIAutomation* automation;
  HWND window;
  ULONGLONG deadline = GetTickCount64() + 400;
  int remaining = 64;
  std::vector<std::unique_ptr<SecretFillTarget>> fields;

  bool Visit(IAccessible* object, LONG child, int depth) {
    if (--remaining < 0 || depth > 6 || GetTickCount64() >= deadline || fields.size() > 2) return false;
    LONG role = 0;
    if (!AccessibleRole(object, child, &role)) return false;
    if (role == ROLE_SYSTEM_TEXT) {
      VARIANT id;
      VariantInit(&id);
      id.vt = VT_I4;
      id.lVal = child;
      LONG x = 0, y = 0, width = 0, height = 0;
      if (FAILED(object->accLocation(&x, &y, &width, &height, id)) || width <= 0 || height <= 0 ||
          static_cast<int64_t>(x) + width > LONG_MAX || static_cast<int64_t>(y) + height > LONG_MAX) return false;
      const POINT center{x + width / 2, y + height / 2};
      auto resolved = AccessibleAtPoint(automation, center, window);
      const auto* native = dynamic_cast<const AccessibleTarget*>(resolved.get());
      ComPtr<IUnknown> identity;
      if (!native || FAILED(object->QueryInterface(IID_PPV_ARGS(&identity)))) return false;
      AccessibleTarget expected;
      expected.automation = automation;
      expected.accessible = object;
      expected.identity = identity;
      expected.child = child;
      expected.window = window;
      if (!expected.Same(*native)) return false;
      fields.push_back(std::move(resolved));
      return fields.size() <= 2;
    }
    if (depth > 0 && (role == ROLE_SYSTEM_DIALOG || role == ROLE_SYSTEM_DOCUMENT || role == ROLE_SYSTEM_WINDOW)) {
      return false;
    }
    if (child != CHILDID_SELF) return true;
    LONG count = 0;
    if (FAILED(object->get_accChildCount(&count)) || count < 0 || count > remaining) return false;
    if (count == 0) return true;
    std::vector<VARIANT> children(count);
    LONG obtained = 0;
    bool valid = AccessibleChildren(object, 0, count, children.data(), &obtained) == S_OK && obtained == count;
    for (LONG index = 0; index < count; ++index) {
      auto& item = children[index];
      if (valid && item.vt == VT_DISPATCH && item.pdispVal) {
        ComPtr<IAccessible> accessible_child;
        valid = SUCCEEDED(item.pdispVal->QueryInterface(IID_PPV_ARGS(&accessible_child))) &&
            Visit(accessible_child.Get(), CHILDID_SELF, depth + 1);
      } else if (valid && item.vt == VT_I4) {
        valid = Visit(object, item.lVal, depth + 1);
      } else if (valid) {
        valid = false;
      }
      VariantClear(&item);
    }
    return valid;
  }
};

std::unique_ptr<SecretFillTarget> AccessibleTarget::Partner() const {
  ComPtr<IAccessible> parent = accessible;
  const auto deadline = GetTickCount64() + 400;
  for (int depth = 0; depth < 8 && GetTickCount64() < deadline; ++depth) {
    if (depth > 0 || child == CHILDID_SELF) {
      ComPtr<IDispatch> next;
      if (FAILED(parent->get_accParent(&next)) || !next || FAILED(next.As(&parent))) return nullptr;
    }
    HWND native = nullptr;
    LONG role = 0;
    if (FAILED(WindowFromAccessibleObject(parent.Get(), &native)) || !native ||
        GetAncestor(native, GA_ROOT) != window || !AccessibleRole(parent.Get(), CHILDID_SELF, &role)) return nullptr;
    const bool boundary = role == ROLE_SYSTEM_DIALOG;
    if (!boundary && role != ROLE_SYSTEM_GROUPING) continue;
    AccessiblePairScan scan{automation.Get(), window, deadline};
    if (!scan.Visit(parent.Get(), CHILDID_SELF, 0)) return nullptr;
    if (scan.fields.size() < 2 && !boundary) continue;
    return GetTickCount64() < deadline ? SelectSecretPartner(*this, std::move(scan.fields)) : nullptr;
  }
  return nullptr;
}
}

SecretTargetResolver CreateSecretTargetResolver() {
  ComPtr<IUIAutomation> automation;
  CoCreateInstance(CLSID_CUIAutomation8, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&automation));
  ComPtr<IUIAutomation2> automation2;
  if (automation && SUCCEEDED(automation.As(&automation2))) {
    automation2->put_ConnectionTimeout(500);
    automation2->put_TransactionTimeout(500);
  }
  return [automation](POINT point, HWND target, const SecretFillTarget* previous) -> std::unique_ptr<SecretFillTarget> {
    if (!WindowMatches(target, point)) return nullptr;
    if (dynamic_cast<const AccessibleTarget*>(previous)) return AccessibleAtPoint(automation.Get(), point, target);
    if (dynamic_cast<const AutomationTarget*>(previous)) return AutomationAtPoint(automation.Get(), point, target);
    auto element = AutomationAtPoint(automation.Get(), point, target);
    if (element) return element;
    return AccessibleAtPoint(automation.Get(), point, target);
  };
}
