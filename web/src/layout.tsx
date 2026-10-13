import { useState } from "preact/hooks";
import type { Block, LayoutItem, PageLayout, RowLayout } from "./store";
import { Icon } from "./icons";
import { useWidget } from "./hooks";
import { Widget } from "./widgets";

function Cell({ id }: { id: string }) {
  const w = useWidget(id);
  if (w.vis === false) return null;
  const size = Array.isArray(w.size) ? w.size[0] : typeof w.size === "number" ? w.size : 1;
  return <div class="cell" style={`flex:${size} 1 0;min-width:0;display:flex;flex-direction:column`}><Widget id={id} /></div>;
}

function Row({ row }: { row: RowLayout }) {
  const w = useWidget(row.id);
  if (w.vis === false) return null;
  return <div class="row" data-id={row.id}>{row.items.map((id) => <Cell key={id} id={id} />)}</div>;
}

const Items = ({ items }: { items: LayoutItem[] }) => <>{items.map((it) => (typeof it === "string" ? <Widget key={it} id={it} /> : <Row key={it.id} row={it} />))}</>;

function Group({ block }: { block: Block }) {
  const w = useWidget(block.id);
  const [open, setOpen] = useState(true);
  if (w.vis === false) return null;
  const fold = !!w.fold;
  return (
    <section class="card" data-id={block.id}>
      {(w.lbl || w.icon) && (
        <div class={`ghead ${fold ? "fold" : ""} ${open ? "" : "closed"}`} onClick={() => fold && setOpen(!open)}>
          {w.icon && <Icon name={w.icon} size={18} />}<span>{w.lbl}</span>{fold && <Icon name="expand_more" class="chev" />}
        </div>
      )}
      {(open || !fold) && <Items items={block.items} />}
    </section>
  );
}

export function Page({ page }: { page: PageLayout }) {
  return (
    <div class="blocks">
      {page.blocks.map((b) => (b.kind === "group" ? <Group key={b.id} block={b} /> : <div key={b.id} class="card free"><Items items={b.items} /></div>))}
    </div>
  );
}
