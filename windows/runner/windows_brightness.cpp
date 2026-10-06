#include "windows_brightness.h"
#include <wbemidl.h>
#include <wrl/client.h>
#include <flutter/standard_method_codec.h>
#include <algorithm>
#include <cmath>
#include <cwctype>
#include <string>

namespace {
using Microsoft::WRL::ComPtr;
struct BStr {
  explicit BStr(const wchar_t* text) : value(SysAllocString(text)) {}
  ~BStr() { SysFreeString(value); }
  BSTR value;
};
struct Variant {
  Variant() { VariantInit(&value); }
  ~Variant() { VariantClear(&value); }
  VARIANT value;
};
struct ComScope {
  ComScope() : result(CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED)) {}
  ~ComScope() { if (SUCCEEDED(result)) CoUninitialize(); }
  HRESULT result;
};

std::wstring MonitorId(HWND view) {
  MONITORINFOEXW monitor{};
  monitor.cbSize = sizeof(monitor);
  DISPLAY_DEVICEW display{};
  display.cb = sizeof(display);
  if (!GetMonitorInfoW(MonitorFromWindow(view, MONITOR_DEFAULTTONEAREST),
      reinterpret_cast<MONITORINFO*>(&monitor)) ||
      !EnumDisplayDevicesW(monitor.szDevice, 0, &display, 0)) return {};
  std::wstring id(display.DeviceID);
  const auto start = id.find(L'\\');
  if (start == std::wstring::npos) return {};
  id = id.substr(start + 1, id.find(L'\\', start + 1) - start - 1);
  std::transform(id.begin(), id.end(), id.begin(),
      [](wchar_t c) { return static_cast<wchar_t>(towupper(c)); });
  return L"\\" + id + L"\\";
}

ComPtr<IWbemClassObject> QueryPanel(IWbemServices* services, HWND view,
                                  const wchar_t* query) {
  const auto monitor_id = MonitorId(view);
  if (monitor_id.empty()) return nullptr;
  ComPtr<IEnumWbemClassObject> rows;
  BStr language(L"WQL"), statement(query);
  if (FAILED(services->ExecQuery(language.value, statement.value,
      WBEM_FLAG_FORWARD_ONLY | WBEM_FLAG_RETURN_IMMEDIATELY, nullptr, &rows))) return nullptr;
  for (;;) {
    ComPtr<IWbemClassObject> row;
    ULONG count = 0;
    if (FAILED(rows->Next(2000, 1, &row, &count)) || count == 0) return nullptr;
    Variant instance;
    if (FAILED(row->Get(L"InstanceName", 0, &instance.value, nullptr, nullptr)) ||
        instance.value.vt != VT_BSTR) continue;
    std::wstring name(instance.value.bstrVal);
    std::transform(name.begin(), name.end(), name.begin(),
        [](wchar_t c) { return static_cast<wchar_t>(towupper(c)); });
    if (name.find(monitor_id) != std::wstring::npos) return row;
  }
}

ComPtr<IWbemServices> Connect() {
  ComPtr<IWbemLocator> locator;
  if (FAILED(CoCreateInstance(CLSID_WbemLocator, nullptr, CLSCTX_INPROC_SERVER,
      IID_PPV_ARGS(&locator)))) return nullptr;
  ComPtr<IWbemServices> services;
  BStr space(L"ROOT\\WMI");
  if (FAILED(locator->ConnectServer(space.value, nullptr, nullptr, nullptr, 0,
      nullptr, nullptr, &services))) return nullptr;
  if (FAILED(CoSetProxyBlanket(services.Get(), RPC_C_AUTHN_WINNT, RPC_C_AUTHZ_NONE,
      nullptr, RPC_C_AUTHN_LEVEL_CALL, RPC_C_IMP_LEVEL_IMPERSONATE, nullptr, EOAC_NONE))) return nullptr;
  return services;
}

bool SetBrightness(IWbemServices* services, IWbemClassObject* panel, double value) {
  ComPtr<IWbemClassObject> type, parameters, arguments, output;
  BStr class_name(L"WmiMonitorBrightnessMethods"), method(L"WmiSetBrightness");
  if (FAILED(services->GetObject(class_name.value, 0, nullptr, &type, nullptr)) ||
      FAILED(type->GetMethod(method.value, 0, &parameters, nullptr)) ||
      FAILED(parameters->SpawnInstance(0, &arguments))) return false;
  Variant brightness, timeout, path;
  brightness.value.vt = VT_UI1;
  brightness.value.bVal = static_cast<BYTE>(std::lround(value * 100));
  // WMI maps CIM uint8 to VT_UI1 and uint32 timeout to VT_I4.
  timeout.value.vt = VT_I4;
  timeout.value.lVal = 0;
  if (FAILED(arguments->Put(L"Brightness", 0, &brightness.value, 0)) ||
      FAILED(arguments->Put(L"Timeout", 0, &timeout.value, 0)) ||
      FAILED(panel->Get(L"__PATH", 0, &path.value, nullptr, nullptr)) ||
      path.value.vt != VT_BSTR) return false;
  if (FAILED(services->ExecMethod(path.value.bstrVal, method.value, 0, nullptr,
      arguments.Get(), &output, nullptr))) return false;
  // Some monitor providers (including built-in panels) omit ReturnValue.
  // In that case the successful ExecMethod HRESULT is the result.
  if (!output) return true;
  Variant status;
  const HRESULT read = output->Get(L"ReturnValue", 0, &status.value, nullptr, nullptr);
  if (read == static_cast<HRESULT>(WBEM_E_NOT_FOUND)) return true;
  if (FAILED(read)) return false;
  if (status.value.vt == VT_EMPTY || status.value.vt == VT_NULL) return true;
  return
      (status.value.vt == VT_I4 || status.value.vt == VT_UI4) && status.value.ulVal == 0;
}
}  // namespace

WindowsBrightness::WindowsBrightness(flutter::BinaryMessenger* messenger, HWND view) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "pilipili/display", &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([view](const auto& call, auto result) {
    const bool get = call.method_name() == "getBrightness";
    if (!get && call.method_name() != "setBrightness") { result->NotImplemented(); return; }
    ComScope com;
    auto services = Connect();
    auto panel = services ? QueryPanel(services.Get(), view, get
        ? L"SELECT * FROM WmiMonitorBrightness WHERE Active=TRUE"
        : L"SELECT * FROM WmiMonitorBrightnessMethods WHERE Active=TRUE") : nullptr;
    if (!panel) { result->Error("unavailable", "This display does not expose WMI brightness"); return; }
    if (get) {
      Variant brightness;
      const HRESULT read = panel->Get(L"CurrentBrightness", 0, &brightness.value, nullptr, nullptr);
      const LONG value = brightness.value.vt == VT_UI1 ? brightness.value.bVal :
          (brightness.value.vt == VT_I4 ? brightness.value.lVal : -1);
      if (SUCCEEDED(read) && value >= 0 && value <= 100) {
        result->Success(flutter::EncodableValue(value / 100.0));
      } else { result->Error("unavailable", "Unable to read display brightness"); }
    } else {
      const auto* value = call.arguments() ? std::get_if<double>(call.arguments()) : nullptr;
      if (!value || !std::isfinite(*value) || *value < 0 || *value > 1) {
        result->Error("invalid", "Brightness must be between zero and one"); return;
      }
      if (SetBrightness(services.Get(), panel.Get(), *value)) result->Success();
      else result->Error("unavailable", "Unable to set display brightness");
    }
  });
}
WindowsBrightness::~WindowsBrightness() { channel_->SetMethodCallHandler(nullptr); }
