import { useState } from 'react';
import type { FC } from 'react';
import type { CategoryStat, MonthlyTrend } from '../lib/api';
import { formatMoney, formatPercent } from '../lib/format.ts';

/* Fluent brand single-hue scale, token-driven */
const DONUT_SCALE = [
  'var(--donut-1)',
  'var(--donut-2)',
  'var(--donut-3)',
  'var(--donut-4)',
  'var(--donut-5)',
];

const donutColor = (index: number) => DONUT_SCALE[index % DONUT_SCALE.length];

/* ============================== DonutChart ============================== */

interface DonutChartProps {
  data: CategoryStat[];
  ariaLabel?: string;
}

export const DonutChart: FC<DonutChartProps> = ({ data, ariaLabel = '支出构成环形图' }) => {
  const [selectedId, setSelectedId] = useState<number | null>(null);

  const R = 54;
  const CIRC = 2 * Math.PI * R;
  const total = data.reduce((s, d) => s + d.amount, 0);
  const selected = data.find((d) => d.id === selectedId) ?? null;

  let offset = 0;
  const segments =
    total > 0
      ? data.map((d, i) => {
          const len = (d.amount / total) * CIRC;
          const seg = {
            key: d.id,
            color: donutColor(i),
            dasharray: `${len} ${CIRC - len}`,
            dashoffset: -offset,
          };
          offset += len;
          return seg;
        })
      : [];

  const handleSelect = (id: number) => setSelectedId((prev) => (prev === id ? null : id));

  return (
    <div className="flex flex-col gap-3">
      <div className="flex items-center gap-5 flex-wrap">
        <svg
          width={140}
          height={140}
          viewBox="0 0 140 140"
          role="img"
          aria-label={ariaLabel}
          className="flex-shrink-0"
        >
          <g transform="rotate(-90 70 70)" fill="none" strokeWidth="16" strokeLinecap="butt">
            <circle cx="70" cy="70" r={R} stroke="var(--surface-sunken)" />
            {segments.map((s) => (
              <circle
                key={s.key}
                cx="70"
                cy="70"
                r={R}
                stroke={s.color}
                strokeDasharray={s.dasharray}
                strokeDashoffset={s.dashoffset}
              />
            ))}
          </g>
          <text x="70" y="66" textAnchor="middle" fontSize="11" fill="var(--fg-3)">
            支出合计
          </text>
          <text
            x="70"
            y="86"
            textAnchor="middle"
            fontSize="17"
            fontWeight="650"
            fill="var(--fg)"
            letterSpacing="-0.5"
          >
            {formatMoney(total, { sign: 'none' })}
          </text>
        </svg>

        {/* Legend */}
        {data.length > 0 && (
          <div className="flex-1 min-w-[190px] flex flex-col gap-0.5">
            {data.map((d, i) => {
              const pressed = selectedId === d.id;
              return (
                <button
                  key={d.id}
                  type="button"
                  aria-pressed={pressed}
                  onClick={() => handleSelect(d.id)}
                  className={`flex items-center gap-2 px-2 py-1.5 rounded-[var(--r-xs)] cursor-pointer border text-left transition-colors duration-[var(--d1)] ${
                    pressed
                      ? 'bg-[var(--brand-soft)] border-[var(--brand-line)]'
                      : 'border-transparent hover:bg-[var(--surface-hover)]'
                  }`}
                >
                  <i className="w-2 h-2 rounded-[var(--r-nano)] flex-shrink-0" style={{ background: donutColor(i) }} />
                  <b className="flex-1 text-[12.5px] font-medium text-[var(--fg)] truncate">{d.name}</b>
                  <em className="not-italic num text-[12.5px] font-semibold text-[var(--fg)]">
                    {formatMoney(d.amount, { sign: 'none' })}
                  </em>
                  <s className="no-underline num text-[11.5px] text-[var(--fg-3)] w-[42px] text-right">
                    {formatPercent(d.percentage)}
                  </s>
                </button>
              );
            })}
          </div>
        )}
      </div>

      {/* Same-viewport drilldown for the selected category */}
      {selected && (
        <div className="mt-1 p-3 rounded-[var(--r-sm)] bg-[var(--surface-sunken)] border border-[var(--line)] animate-fade">
          <div className="flex justify-between items-baseline">
            <b className="text-[12.5px] text-[var(--fg)]">{selected.name} · 细分标签</b>
            <span className="num text-[11.5px] text-[var(--fg-3)]">
              {formatMoney(selected.amount, { sign: 'none' })}
            </span>
          </div>
          {selected.tags.length === 0 ? (
            <div className="mt-2 text-[11.5px] text-[var(--fg-muted)]">该分类下暂无细分标签支出</div>
          ) : (
            <div className="flex flex-wrap gap-1.5 mt-2">
              {selected.tags.map((tg) => (
                <span
                  key={tg.id}
                  className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-[var(--r-xs)] bg-[var(--surface)] border border-[var(--line)] text-xs"
                >
                  <b className="font-semibold text-[var(--fg)]">{tg.name}</b>
                  <s className="no-underline num text-[11px] text-[var(--fg-3)]">
                    {formatMoney(tg.amount, { sign: 'none' })}
                  </s>
                  <s className="no-underline num text-[11px] text-[var(--fg-3)]">{formatPercent(tg.percentage)}</s>
                </span>
              ))}
            </div>
          )}
        </div>
      )}
    </div>
  );
};

/* ============================== TrendChart ============================== */

interface TrendChartProps {
  data: MonthlyTrend[];
  ariaLabel?: string;
}

export const TrendChart: FC<TrendChartProps> = ({ data, ariaLabel = '近六个月收支趋势' }) => {
  const W = 340;
  const H = 150;
  const TOP = 30;
  const BOTTOM = 120;

  const maxY = Math.max(...data.map((t) => Math.max(t.expense, t.income)), 1);
  const step = data.length > 1 ? (W - 28) / (data.length - 1) : 0;
  const xAt = (i: number) => (data.length > 1 ? 14 + i * step : W / 2);
  const yAt = (v: number) => BOTTOM - (v / maxY) * (BOTTOM - TOP);

  const linePath = (pick: (t: MonthlyTrend) => number) =>
    data.map((t, i) => `${i === 0 ? 'M' : 'L'}${xAt(i)} ${yAt(pick(t))}`).join(' ');

  const areaPath =
    data.length > 1
      ? `${linePath((t) => t.expense)} L${xAt(data.length - 1)} ${BOTTOM} L${xAt(0)} ${BOTTOM} Z`
      : '';

  const last = data.length - 1;

  return (
    <svg viewBox={`0 0 ${W} ${H}`} style={{ width: '100%', height: 'auto' }} role="img" aria-label={ariaLabel}>
      <defs>
        <linearGradient id="trend-expense-fill" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor="var(--expense)" stopOpacity=".26" />
          <stop offset="100%" stopColor="var(--expense)" stopOpacity="0" />
        </linearGradient>
      </defs>

      {/* Grid */}
      <g stroke="var(--line)" strokeWidth="1">
        {[30, 60, 90, 120].map((y) => (
          <line key={y} x1="0" y1={y} x2={W} y2={y} />
        ))}
      </g>

      {/* Expense area + line */}
      {data.length > 1 && <path d={areaPath} fill="url(#trend-expense-fill)" />}
      {data.length > 1 && (
        <path
          d={linePath((t) => t.expense)}
          fill="none"
          stroke="var(--expense)"
          strokeWidth="2"
          strokeLinecap="round"
          strokeLinejoin="round"
        />
      )}

      {/* Income line */}
      {data.length > 1 && (
        <path
          d={linePath((t) => t.income)}
          fill="none"
          stroke="var(--income)"
          strokeWidth="2"
          strokeLinecap="round"
          strokeLinejoin="round"
        />
      )}

      {/* Points — last month emphasized */}
      {data.map((t, i) => (
        <g key={t.month}>
          <circle
            cx={xAt(i)}
            cy={yAt(t.expense)}
            r={i === last ? 4.5 : 3}
            fill={i === last ? 'var(--expense)' : 'var(--surface)'}
            stroke="var(--expense)"
            strokeWidth="2"
          />
          <circle
            cx={xAt(i)}
            cy={yAt(t.income)}
            r={i === last ? 4.5 : 3}
            fill={i === last ? 'var(--income)' : 'var(--surface)'}
            stroke="var(--income)"
            strokeWidth="2"
          />
        </g>
      ))}

      {/* Month labels */}
      <g fill="var(--fg-3)" fontSize="10.5" textAnchor="middle">
        {data.map((t, i) => (
          <text key={t.month} x={xAt(i)} y={139}>
            {t.month.substring(5)}月
          </text>
        ))}
      </g>
    </svg>
  );
};
