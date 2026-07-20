import { postMessage } from "./bridge.js";
import { uiState } from "./state.js";

export interface AudioDeviceInfo {
  name: string;
  typeName: string;
}

export interface AudioDeviceListPayload {
  inputDevices: AudioDeviceInfo[];
  outputDevices: AudioDeviceInfo[];
  currentInputDeviceName: string;
  currentOutputDeviceName: string;
  deviceTypeName: string;
  sampleRates: number[];
  currentSampleRate: number;
  bufferSizes: number[];
  currentBufferSize: number;
}

let startPageResolve: (() => void) | null = null;
let deviceList: AudioDeviceListPayload | null = null;
let dismissed = false;

function el<T extends HTMLElement = HTMLElement>(id: string): T | null {
  return document.getElementById(id) as T | null;
}

function showStartPageUI(page: HTMLElement): void {
  page.removeAttribute("hidden");
  requestAnimationFrame(() => page.classList.add("start-page-visible"));
  bindEvents();
}

function createStartPagePromise(): Promise<void> {
  return new Promise((resolve) => {
    startPageResolve = resolve;
  });
}

function createMockDeviceList(): AudioDeviceListPayload {
  return {
    inputDevices: [
      { name: "Built-in Microphone", typeName: "CoreAudio" },
      { name: "Scarlett 2i2 USB", typeName: "CoreAudio" },
    ],
    outputDevices: [
      { name: "Built-in Output", typeName: "CoreAudio" },
      { name: "Scarlett 2i2 USB", typeName: "CoreAudio" },
    ],
    currentInputDeviceName: "Scarlett 2i2 USB",
    currentOutputDeviceName: "Scarlett 2i2 USB",
    deviceTypeName: "CoreAudio",
    sampleRates: [44100, 48000, 88200, 96000],
    currentSampleRate: 48000,
    bufferSizes: [32, 64, 128, 256, 512, 1024],
    currentBufferSize: 128,
  };
}

export function showStartPage(): Promise<void> {
  const page = el("start-page");
  if (!page) return Promise.resolve();

  dismissed = false;

  const hasBridge = typeof (window as any).IPlugSendMsg === "function";

  if (!hasBridge) {
    // Local dev (no C++ backend): show with mock data for testing
    showStartPageUI(page);
    setTimeout(() => applyAudioDeviceList(createMockDeviceList()), 500);
    setTimeout(() => { if (!dismissed) dismissStartPage(); }, 30000);
    return createStartPagePromise();
  }

  // In JUCE WebView: poll for environment data, then decide
  return new Promise<void>(async (resolve) => {
    for (let i = 0; i < 50; i++) {
      if (typeof uiState.environment?.standalone === "boolean") break;
      await new Promise((r) => setTimeout(r, 10));
    }

    if (uiState.environment?.standalone !== true) {
      // DAW plugin mode: skip start page
      page.setAttribute("hidden", "");
      resolve();
      return;
    }

    // Standalone mode: show start page with real device list
    showStartPageUI(page);
    requestAnimationFrame(() => {
      postMessage({ type: "getAudioDevices" });
    });
    startPageResolve = resolve;
    // Safety auto-dismiss after 30s
    setTimeout(() => {
      if (!dismissed) dismissStartPage();
    }, 30000);
  });
}

function bindEvents(): void {
  const continueBtn = el<HTMLButtonElement>("start-page-continue");
  const skipBtn = el<HTMLButtonElement>("start-page-skip");
  const openPrefsBtn = el<HTMLButtonElement>("start-page-open-preferences");
  const inputSelect = el<HTMLSelectElement>("start-input-device");
  const outputSelect = el<HTMLSelectElement>("start-output-device");

  if (continueBtn && !continueBtn.dataset.bound) {
    continueBtn.dataset.bound = "true";
    continueBtn.addEventListener("click", () => {
      applyAudioDeviceSelection();
      dismissStartPage();
    });
  }

  if (skipBtn && !skipBtn.dataset.bound) {
    skipBtn.dataset.bound = "true";
    skipBtn.addEventListener("click", () => {
      dismissStartPage();
    });
  }

  if (openPrefsBtn && !openPrefsBtn.dataset.bound) {
    openPrefsBtn.dataset.bound = "true";
    openPrefsBtn.addEventListener("click", () => {
      postMessage({ type: "openAudioPreferences" });
    });
  }

  if (inputSelect && !inputSelect.dataset.bound) {
    inputSelect.dataset.bound = "true";
  }

  if (outputSelect && !outputSelect.dataset.bound) {
    outputSelect.dataset.bound = "true";
  }
}

function applyAudioDeviceSelection(): void {
  if (!deviceList) return;

  const inputSelect = el<HTMLSelectElement>("start-input-device");
  const outputSelect = el<HTMLSelectElement>("start-output-device");
  const sampleRateSelect = el<HTMLSelectElement>("start-sample-rate");
  const bufferSizeSelect = el<HTMLSelectElement>("start-buffer-size");

  const inputDeviceName = inputSelect?.value ?? deviceList.currentInputDeviceName;
  const outputDeviceName = outputSelect?.value ?? deviceList.currentOutputDeviceName;
  const sampleRate = sampleRateSelect?.value ? Number(sampleRateSelect.value) : deviceList.currentSampleRate;
  const bufferSize = bufferSizeSelect?.value ? Number(bufferSizeSelect.value) : deviceList.currentBufferSize;

  // Don't send if no device names selected (e.g. no devices available)
  if (!inputDeviceName && !outputDeviceName) return;

  postMessage({
    type: "setAudioDevice",
    inputDeviceName,
    outputDeviceName,
    deviceTypeName: deviceList.deviceTypeName,
    sampleRate,
    bufferSize,
  });
}

function dismissStartPage(): void {
  if (dismissed) return;
  dismissed = true;

  const page = el("start-page");
  if (!page) return;

  page.classList.remove("start-page-visible");
  page.setAttribute("hidden", "");

  if (startPageResolve) {
    startPageResolve();
    startPageResolve = null;
  }
}

function populateSelect(select: HTMLSelectElement | null, devices: AudioDeviceInfo[], currentName: string): void {
  if (!select) return;

  select.innerHTML = "";
  if (!devices || devices.length === 0) {
    const opt = document.createElement("option");
    opt.value = "";
    opt.textContent = "No devices found";
    select.appendChild(opt);
    select.disabled = true;
    return;
  }

  select.disabled = false;
  for (const device of devices) {
    const opt = document.createElement("option");
    opt.value = device.name;
    opt.textContent = device.name;
    if (device.name === currentName) {
      opt.selected = true;
    }
    select.appendChild(opt);
  }
}

function populateNumberSelect(select: HTMLSelectElement | null, values: number[], currentValue: number): void {
  if (!select) return;

  select.innerHTML = "";
  if (!values || values.length === 0) {
    const opt = document.createElement("option");
    opt.value = "";
    opt.textContent = "—";
    select.appendChild(opt);
    select.disabled = true;
    return;
  }

  select.disabled = false;
  for (const val of values) {
    const opt = document.createElement("option");
    opt.value = String(val);
    opt.textContent = val >= 1000 ? `${(val / 1000).toFixed(0)} kHz` : String(val);
    if (val === currentValue) {
      opt.selected = true;
    }
    select.appendChild(opt);
  }
}

export function applyAudioDeviceList(payload: AudioDeviceListPayload): void {
  deviceList = payload;

  populateSelect(el<HTMLSelectElement>("start-input-device"), payload.inputDevices, payload.currentInputDeviceName);
  populateSelect(el<HTMLSelectElement>("start-output-device"), payload.outputDevices, payload.currentOutputDeviceName);
  populateNumberSelect(el<HTMLSelectElement>("start-sample-rate"), payload.sampleRates, payload.currentSampleRate);
  populateNumberSelect(el<HTMLSelectElement>("start-buffer-size"), payload.bufferSizes, payload.currentBufferSize);

  const errorEl = el("start-page-error");
  const errorText = el("start-page-error-text");
  if (errorEl && errorText) {
    const warnings: string[] = [];
    if (!payload.inputDevices || payload.inputDevices.length === 0) {
      warnings.push("No audio input devices detected");
    }
    if (!payload.outputDevices || payload.outputDevices.length === 0) {
      warnings.push("No audio output devices detected");
    }
    if (warnings.length > 0) {
      errorText.textContent = warnings.join(". ") + ".";
      errorEl.removeAttribute("hidden");
    } else {
      errorEl.setAttribute("hidden", "");
    }
  }
}
