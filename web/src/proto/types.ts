// Hand-written mirror of protocol/schema/v1. Unknown keys are kept on widgets and ignored elsewhere.
export type Value = boolean | number | string | number[] | (string | number)[][];

export interface Widget {
  id: string;
  ty: string;
  lbl?: string;
  grp?: string;
  page?: string;
  row?: string;
  size?: number | [number, number];
  sq?: boolean;
  dis?: boolean;
  vis?: boolean;
  hint?: string;
  icon?: string;
  ro?: boolean;
  color?: string;
  unit?: string;
  fmt?: string;
  hold?: boolean;
  on?: string;
  off?: string;
  min?: number;
  max?: number;
  step?: number;
  spin?: boolean;
  maxlen?: number;
  secret?: boolean;
  re?: string;
  rows?: number;
  opts?: string[];
  style?: string;
  mode?: string;
  center?: boolean;
  exp?: boolean;
  zones?: { from: number; to: number; color: string }[];
  digits?: number;
  rgb?: boolean;
  series?: { id: string; lbl?: string; color?: string }[];
  win?: number;
  legend?: boolean;
  vals?: boolean;
  cap?: number;
  cols?: { lbl?: string; w?: number; align?: string }[];
  src?: string;
  zoom?: number;
  text?: string;
  fold?: boolean;
  [k: string]: unknown;
}

export type Cap = "wifi" | "ota" | "otaurl" | "chart" | "ble" | "ntp" | "ntfy" | "pin" | "reboot" | "info";

export interface HelloMsg { t: "hello"; v: number; name: string; id: string; proj?: string; icon?: string; fw?: string; auth: "none" | "pin"; ok: boolean; nonce?: string; lock?: number; up: number; caps: Cap[] }
export interface AuthMsg { t: "auth"; ok: boolean; tok?: string; left?: number; lock?: number }
export interface UiMsg { t: "ui"; rev: number; w: Widget[] }
export interface UpdMsg { t: "upd"; v: Record<string, Value> }
export interface PtsMsg { t: "pts"; id: string; s: string; p: [number, number][] }
export interface ToastMsg { t: "toast"; lvl: "info" | "warn" | "err"; msg: string }
export interface LogMsg { t: "log"; msg: string; id?: string; c?: string; ts?: number }
export interface PropMsg { t: "prop"; id: string; p: Partial<Widget> }
export interface DlgMsg { t: "dlg"; id: string; kind?: "confirm" | "prompt"; title?: string; msg?: string; def?: string; timeout?: number; close?: true }
export interface SysMsg { t: "sys"; cmd: string; ok?: boolean; msg?: string; [k: string]: unknown }
export interface ErrMsg { t: "err"; code: number; msg: string; ref?: string }

export type D2C = HelloMsg | AuthMsg | UiMsg | UpdMsg | PtsMsg | ToastMsg | LogMsg | PropMsg | DlgMsg | SysMsg | ErrMsg;

export interface SysInfo { chip?: string; fw?: string; repo?: string; about?: string; rr?: string; heap?: number; heapmin?: number; up?: number; ip?: string; ssid?: string; rssi?: number; mac?: string; time?: number; clients?: number }
export interface WifiStatus { st?: "connecting" | "connected" | "failed" | "ap"; ip?: string; ssid?: string; rssi?: number }
export interface WifiAp { ssid: string; rssi: number; enc: boolean }
