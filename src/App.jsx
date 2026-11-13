import { useEffect, useMemo, useState } from 'react';
import './styles.css';
import Model2Preview from './Model2Preview.jsx';

export const plans = [
  { name: 'VIP 1', rate: 1, capital: 10, directs: 0, volume: 0, accent: 'mint' },
  { name: 'VIP 2', rate: 1.25, capital: 500, directs: 2, volume: 2500, accent: 'cyan' },
  { name: 'VIP 3', rate: 1.5, capital: 2500, directs: 4, volume: 12500, accent: 'blue' },
  { name: 'VIP 4', rate: 2, capital: 10000, directs: 6, volume: 50000, accent: 'violet' },
  { name: 'VIP 5', rate: 2.5, capital: 25000, directs: 10, volume: 125000, accent: 'pink' },
];

const money = value => Number(value).toLocaleString('en-US', { maximumFractionDigits: 2 });
const navigation = [
  ['Home', '#home'], ['Invest', '#plans'], ['Markets', '#markets'],
  ['Referrals', '#referrals'], ['Ranks', '#ranks'], ['Model 2', '#model2-preview'], ['Docs', '#docs'],
];

function Icon({ name, size = 22, className = '' }) {
  const common = { width: size, height: size, viewBox: '0 0 24 24', fill: 'none', stroke: 'currentColor', strokeWidth: 1.8, strokeLinecap: 'round', strokeLinejoin: 'round', className, 'aria-hidden': true };
  const icons = {
    shield: <><path d="m12 2 9 4v6c0 6-3.8 9-9 10-5.2-1-9-4-9-10V6l9-4Z"/><path d="m8 12 2.5 2.5L16 9"/></>,
    users: <><path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.87M16 3.13a4 4 0 0 1 0 7.75"/></>,
    crown: <><path d="m2 7 5 4 5-7 5 7 5-4-2 12H4L2 7Z"/><path d="M4 22h16"/></>,
    stack: <><path d="m12 2 9 5-9 5-9-5 9-5Z"/><path d="m3 12 9 5 9-5M3 17l9 5 9-5"/></>,
    chart: <><path d="M3 20h18M5 17v-5h4v5M11 17V8h4v9M17 17V4h4v13"/></>,
    head: <><path d="M3 14v-3a9 9 0 0 1 18 0v3M3 14h4v7H5a2 2 0 0 1-2-2v-5ZM21 14h-4v7h2a2 2 0 0 0 2-2v-5Z"/></>,
    bolt: <><path d="m13 2-9 12h7l-1 8 10-12h-7l0-8Z"/></>,
    wallet: <><path d="M20 7V5a2 2 0 0 0-2-2H5a3 3 0 0 0-3 3v12a3 3 0 0 0 3 3h15a2 2 0 0 0 2-2V9a2 2 0 0 0-2-2H5a3 3 0 0 1 0-6"/><path d="M17 14h3"/></>,
    globe: <><circle cx="12" cy="12" r="10"/><path d="M2 12h20M12 2c3 3 4 6.5 4 10s-1 7-4 10M12 2c-3 3-4 6.5-4 10s1 7 4 10"/></>,
    menu: <><path d="M4 6h16M4 12h16M4 18h16"/></>,
    close: <><path d="M5 5l14 14M19 5 5 19"/></>,
    check: <><path d="m5 12 4 4L19 6"/></>,
    code: <><path d="m8 8-4 4 4 4M16 8l4 4-4 4M14 4l-4 16"/></>,
    info: <><circle cx="12" cy="12" r="10"/><path d="M12 11v6M12 7h.01"/></>,
    arrow: <><path d="M5 12h14m-7-7 7 7-7 7"/></>,
    coins: <><ellipse cx="12" cy="5" rx="9" ry="3"/><path d="M3 5v14c0 1.7 4 3 9 3s9-1.3 9-3V5M3 12c0 1.7 4 3 9 3s9-1.3 9-3"/></>,
  };
  return <svg {...common}>{icons[name] || icons.info}</svg>;
}

function Header({ onAccount }) {
  const [menuOpen, setMenuOpen] = useState(false);
  const [active, setActive] = useState('#home');
  return <header className="header" id="top">
    <div className="wide header-inner">
      <a className="brand" href="#home" onClick={() => { setActive('#home'); setMenuOpen(false); }} aria-label="Nexora Markets home">
        <span className="brand-mark">N</span><span className="brand-word">Nexora<span>Markets</span></span>
      </a>
      <div className="chain-pill"><span className="bnb-logo">⬡</span> BNB Smart Chain</div>
      <nav id="main-nav" className={menuOpen ? 'nav nav-open' : 'nav'} aria-label="Main navigation">
        {navigation.map(([label, href]) => <a key={href} className={active === href ? 'active' : ''} href={href} onClick={() => { setActive(href); setMenuOpen(false); }}>{label}</a>)}
      </nav>
      <div className="header-actions">
        <button className="account-btn" type="button" onClick={onAccount}><span className="avatar">●</span> My Account <span className="chev">⌄</span></button>
        <button className="language-btn" type="button" aria-label="Language: English" title="English is the current preview language" onClick={() => document.getElementById('docs')?.scrollIntoView({ behavior: 'smooth' })}><Icon name="globe" size={20}/></button>
        <button className="mobile-toggle" type="button" aria-controls="main-nav" aria-expanded={menuOpen} aria-label={menuOpen ? 'Close menu' : 'Open menu'} onClick={() => setMenuOpen(v => !v)}><Icon name={menuOpen ? 'close' : 'menu'}/></button>
      </div>
    </div>
  </header>;
}

function Hero() {
  return <section className="hero wide" id="home">
    <div className="hero-stars" aria-hidden="true" />
    <div className="hero-art" aria-label="Futuristic neon 3D Nexora coin over midnight mountains" role="img" />
    <div className="hero-content">
      <div className="hero-eyebrow"><Icon name="code" size={18}/> Smart Contract Investing <span className="eyebrow-divider"/><span>Concept Preview</span></div>
      <h1>Nexora <span>Markets</span></h1>
      <h2>Sustainable Investing in the Blockchain Era</h2>
      <p>Explore a proposed Web3 investment model on BNB Smart Chain using USDT. Transparent conditions, a premium market experience and no simulated account balances.</p>
      <div className="hero-cta">
        <a href="#plans" className="btn btn-primary">Explore Investment Plans <Icon name="arrow" size={19}/></a>
        <a href="#referrals" className="btn btn-ghost"><Icon name="users" size={19}/> Referral Rewards <span className="cta-arr">›</span></a>
      </div>
    </div>
  </section>;
}

const markets = [
  { id: 'bitcoin', name: 'BTC/USDT', label: '₿', coinClass: 'btc' },
  { id: 'ethereum', name: 'ETH/USDT', label: '◆', coinClass: 'eth' },
  { id: 'binancecoin', name: 'BNB/USDT', label: '⬡', coinClass: 'bnb' },
  { id: 'tether', name: 'USDT', label: '₮', coinClass: 'usdt' },
];
function useMarketPrices() {
  const [prices, setPrices] = useState(null);
  const [updated, setUpdated] = useState(null);
  useEffect(() => {
    let live = true;
    const controller = new AbortController();
    const fetchPrices = async () => {
      try {
        const res = await fetch('https://api.coingecko.com/api/v3/simple/price?ids=bitcoin,ethereum,binancecoin,tether&vs_currencies=usd&include_24hr_change=true', { signal: controller.signal, headers: { accept: 'application/json' } });
        if (!res.ok) throw Error('Market service unavailable');
        const data = await res.json();
        if (live && data?.bitcoin?.usd && data?.ethereum?.usd) { setPrices(data); setUpdated(new Date()); }
      } catch { /* Do not substitute fabricated prices. */ }
    };
    fetchPrices();
    const interval = setInterval(fetchPrices, 90_000);
    return () => { live = false; clearInterval(interval); controller.abort(); };
  }, []);
  return { prices, updated };
}
function MarketTicker() {
  const { prices, updated } = useMarketPrices();
  return <section className="ticker wide" aria-label="Indicative public cryptocurrency market quotes">
    <div className="ticker-grid">{markets.map(m => {
      const data = prices?.[m.id];
      const pct = data?.usd_24h_change;
      return <div className="quote" key={m.id}>
        <span className={'quote-icon ' + m.coinClass}>{m.label}</span>
        <div className="quote-name">{m.name}<small>{data ? 'Public spot reference' : 'Live feed pending'}</small></div>
        <div className="quote-values"><b>{Number.isFinite(data?.usd) ? '$' + money(data.usd) : '—'}</b><span className={typeof pct === 'number' ? (pct >= 0 ? 'up' : 'down') : 'neutral'}>{Number.isFinite(pct) ? (pct >= 0 ? '+' : '') + pct.toFixed(2) + '%' : '—'}</span></div>
      </div>;
    })}</div>
    <span className="ticker-note">{updated ? 'Source: CoinGecko · ' + updated.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' }) : 'Live pricing is unavailable until the public feed responds; no simulated quotes.'}</span>
  </section>;
}

function PlanCards() {
  return <section className="panel plan-panel" id="plans">
    <div className="section-heading"><div className="section-title"><Icon name="stack" size={31}/><div><h2>Investment Plans</h2><p>Five conditional daily caps based on capital, active directs and team volume.</p></div></div><span className="eyebrow-pill">PROPOSED MODEL</span></div>
    <div className="plan-grid">{plans.map(plan => <article className={'plan-card ' + plan.accent} key={plan.name}>
      <div className="plan-glare"/><Icon name="crown" size={29} className="plan-crown"/>
      <h3>{plan.name}</h3><strong className="plan-rate">{plan.rate.toFixed(2)}<span>%</span></strong><span className="plan-period">Daily cap*</span>
      <div className="plan-rule"/>
      <dl><div><dt><Icon name="coins" size={15}/> Active Capital</dt><dd>≥ {money(plan.capital)} USDT</dd></div><div><dt><Icon name="users" size={15}/> Active Directs</dt><dd>≥ {plan.directs}</dd></div><div><dt><Icon name="stack" size={15}/> Group Volume</dt><dd>{plan.volume ? '≥ ' + money(plan.volume) + ' USDT' : 'Not required'}</dd></div></dl>
    </article>)}</div>
    <p className="legal-note">* Illustration of proposed maximums only. Returns are not guaranteed, accrued or withdrawable. Any distribution requires independently verifiable realized profits, available funding, and eligible status.</p>
  </section>;
}

function StatusPanel() {
  return <section className="panel status-panel" id="protocol">
    <div className="side-heading"><h2><Icon name="shield" size={22}/> Contract Status</h2><span className="status-pill prelaunch"><span className="tiny-dot"/> PRE-LAUNCH</span></div>
    <div className="status-rows"><div><span><b className="icon-bnb">⬡</b> Network</span><strong>BNB Smart Chain</strong></div><div><span><b className="icon-usdt">₮</b> Planned asset</span><strong>USDT (BEP-20)</strong></div><div><span><Icon name="code" size={17}/> Smart contract</span><strong>Not deployed</strong></div><div><span><Icon name="wallet" size={17}/> Wallet transactions</span><strong>Disabled</strong></div></div>
  </section>;
}
function StatsPanel() {
  return <section className="panel stats-panel">
    <div className="side-heading"><h2><Icon name="chart" size={22}/> Platform Metrics</h2><span className="eyebrow-pill">UNVERIFIED</span></div>
    <div className="stat-grid"><div><Icon name="coins" size={25}/><strong>—</strong><span>Verified capital</span></div><div><Icon name="users" size={25}/><strong>—</strong><span>Active users</span></div><div><Icon name="chart" size={25}/><strong>—</strong><span>Settled returns</span></div></div>
    <p className="stat-note">No on-chain deployment or independently verified performance records have been published.</p>
  </section>;
}
function Benefits() {
  const items = [
    { name: 'Support Center', icon: 'head', sub: 'Coming soon' },
    { name: 'Security & Transparency', icon: 'shield', sub: 'Audit pending' },
    { name: '3-Level Referrals', icon: 'users', sub: '15% · 7% · 3%' },
    { name: 'Conditional Daily Caps', icon: 'chart', sub: 'Not guaranteed' },
    { name: 'Automated Settlements', icon: 'bolt', sub: 'Planned feature' },
  ];
  return <section className="benefits wide" aria-label="Platform features">{items.map(item => <div className="benefit" key={item.name}><Icon name={item.icon} size={26}/><b>{item.name}</b><span>{item.sub}</span></div>)}</section>;
}

export function calculateTier(capital, directs, volume) {
  const [a, b, c] = [capital, directs, volume].map(Number);
  if ([a, b, c].some(x => !Number.isFinite(x) || x < 0) || a > 50_000 || !Number.isInteger(b)) return { name: 'CHECK INPUT', rate: '—', info: 'Enter nonnegative values, whole-number directs and up to 50,000 USDT of personal capital.' };
  const matched = plans.filter(p => a >= p.capital && b >= p.directs && c >= p.volume).at(-1);
  return matched ? { name: matched.name, rate: matched.rate.toFixed(2) + '%', info: 'Illustrative thresholds met. Full 24-hour activity, branch concentration and realized profit have NOT been verified.' } : { name: 'NOT ELIGIBLE', rate: '—', info: 'The minimum proposed personal capital is 10 USDT.' };
}

function ExtraSections() {
  const [capital, setCapital] = useState('2500');
  const [directs, setDirects] = useState('4');
  const [volume, setVolume] = useState('12500');
  const [answer, setAnswer] = useState(() => calculateTier(2500, 4, 12500));
  const valid = useMemo(() => [capital, directs, volume].every(x => x !== ''), [capital, directs, volume]);
  return <div className="wide extended">
    <div className="extra-grid">
      <section className="panel extra-panel" id="markets"><div className="small-overline">02 / GLOBAL MARKETS</div><h2>Markets, made accessible.</h2><p>Explore independent public market information. No wallet connection is required for the preview.</p><div className="external-links"><a href="https://www.coingecko.com" target="_blank" rel="noopener noreferrer"><span>◈ &nbsp; Live crypto markets</span><Icon name="arrow" size={18}/></a><a href="https://www.bnbchain.org" target="_blank" rel="noopener noreferrer"><span>⬡ &nbsp; BNB Smart Chain</span><Icon name="arrow" size={18}/></a></div></section>
      <section className="panel extra-panel" id="referrals"><div className="small-overline">03 / COMMUNITY</div><h2>Three-level referral model.</h2><p>Proposed commissions on settled profits, not deposits. Subject to independent funding and eligibility.</p><div className="referral-grid">{[15, 7, 3].map((rate, i) => <div key={rate}><strong>{rate}<span>%</span></strong><small>LEVEL {i + 1}</small></div>)}</div></section>
    </div>
    <section className="panel calculator" id="ranks"><div className="small-overline">04 / ELIGIBILITY SIMULATOR</div><h2>Explore your hypothetical tier.</h2><p>A sample calculation based on the proposed plan. This does not connect accounts, move funds or verify the network.</p>
      <div className="calc-grid"><form onSubmit={e => { e.preventDefault(); if (valid) setAnswer(calculateTier(capital, directs, volume)); }}><label>Own eligible capital (USDT)<input value={capital} type="number" min="0" max="50000" onChange={e => setCapital(e.target.value)}/></label><label>Active direct referrals<input value={directs} type="number" min="0" step="1" onChange={e => setDirects(e.target.value)}/></label><label>Eligible 3-level group volume<input value={volume} type="number" min="0" onChange={e => setVolume(e.target.value)}/></label><button disabled={!valid} className="btn btn-primary" type="submit">Calculate example <Icon name="arrow" size={18}/></button></form>
      <div className="result" role="status" aria-live="polite"><span>HYPOTHETICAL TIER</span><h3>{answer.name}</h3><strong>{answer.rate}</strong><p>{answer.info}</p><small>Actual participation would also require 24-hour activity, a maximum 50% contribution from any single branch, and sufficient realized funds.</small></div></div>
    </section>
    <section className="docs" id="docs"><Icon name="info" size={19}/><p><b>Pre-launch design demonstration.</b> Nexora does not currently provide deposits, withdrawals, wallet access, verified daily returns or a published audited smart contract. All rates shown are illustrative conditional ceilings, not an offer or guarantee of profit.</p></section>
  </div>;
}

function AccountModal({ onClose }) {
  useEffect(() => {
    function key(e) { if (e.key === 'Escape') onClose(); }
    window.addEventListener('keydown', key);
    return () => window.removeEventListener('keydown', key);
  }, [onClose]);
  return <div className="modal-backdrop" role="presentation" onMouseDown={e => { if (e.target === e.currentTarget) onClose(); }}><div className="modal" role="dialog" aria-modal="true" aria-labelledby="account-modal-title"><button className="modal-close" aria-label="Close dialog" onClick={onClose} type="button"><Icon name="close"/></button><div className="modal-icon"><Icon name="wallet" size={32}/></div><h2 id="account-modal-title">Account access is coming soon</h2><p>This is a frontend preview of Nexora Markets. The user dashboard, wallet connection, deposits and withdrawals are not connected to live services.</p><button className="btn btn-primary" onClick={onClose} type="button">Understood <Icon name="check" size={18}/></button></div></div>;
}

export default function App() {
  const [accountOpen, setAccountOpen] = useState(false);
  return <><a className="skip-link" href="#main">Skip to content</a><Header onAccount={() => setAccountOpen(true)}/><main id="main"><Hero/><MarketTicker/><div className="wide dashboard"><PlanCards/><div className="side-column"><StatusPanel/><StatsPanel/></div></div><Benefits/><ExtraSections/><Model2Preview/></main><footer className="footer wide"><div className="footer-brand"><span className="brand-mark">N</span> Nexora <span>Markets</span></div><span>© {new Date().getFullYear()} Nexora Markets · Frontend preview, not a live financial product.</span><a href="#home">Back to top ↑</a></footer>{accountOpen && <AccountModal onClose={() => setAccountOpen(false)}/>}</>;
}