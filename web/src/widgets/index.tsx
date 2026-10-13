import type { FunctionComponent } from "preact";
import type { Widget as W } from "../proto/types";
import { useWidget } from "../hooks";
import { Label } from "./Label";
import { Button } from "./Button";
import { Switch } from "./Switch";
import { Slider } from "./Slider";
import { NumberInput } from "./Number";
import { Text } from "./Text";
import { Textarea } from "./Textarea";
import { Select } from "./Select";
import { Flags } from "./Flags";
import { Color } from "./Color";
import { Datetime } from "./Datetime";
import { Joystick } from "./Joystick";
import { Dpad } from "./Dpad";
import { Gauge } from "./Gauge";
import { Progress } from "./Progress";
import { Display } from "./Display";
import { Led } from "./Led";
import { Chart } from "./Chart";
import { Log } from "./Log";
import { Table } from "./Table";
import { Image } from "./Image";
import { Stream } from "./Stream";
import { Clock } from "./Clock";
import { MapWidget } from "./MapWidget";
import { Header, Spacer, Textblock, Unsupported } from "./Static";

export const registry: Record<string, FunctionComponent<{ w: W }>> = {
  label: Label, button: Button, switch: Switch, slider: Slider, number: NumberInput, text: Text, textarea: Textarea,
  select: Select, flags: Flags, color: Color, datetime: Datetime, joystick: Joystick, dpad: Dpad, gauge: Gauge,
  progress: Progress, display: Display, led: Led, chart: Chart, log: Log, table: Table, image: Image, stream: Stream,
  clock: Clock, map: MapWidget, textblock: Textblock, header: Header, spacer: Spacer,
};

export function Widget({ id }: { id: string }) {
  const w = useWidget(id);
  if (w.vis === false) return null;
  const C = registry[w.ty] ?? Unsupported;
  return <C w={w} />;
}
