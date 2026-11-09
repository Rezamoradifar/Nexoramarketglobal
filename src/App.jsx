import { useState } from 'react';
import './styles.css';

export const plans = [
  {name:'VIP 01',rate:1,capital:10,directs:0,volume:0,accent:'mint'},
  {name:'VIP 02',rate:1.25,capital:500,directs:2,volume:2500,accent:'cyan'},
  {name:'VIP 03',rate:1.5,capital:2500,directs:4,volume:12500,accent:'blue'},
  {name:'VIP 04',rate:2,capital:10000,directs:6,volume:50000,accent:'violet'},
  {name:'VIP 05',rate:2.5,capital:25000,directs:10,volume:125000,accent:'pink'}
];

export function calculateTier(capital, directs, volume) {
  const values = [capital, directs, volume].map(Number);
  if (values.some(v => !Number.isFinite(v) || v < 0) || values[0] > 50000 || !Number.isInteger(values[1])) {
    return {name:'CHECK INPUT',rate:'—',info:'Use nonnegative values, whole-number directs and at most 50,000 USDT own capital.'};
  }
  const p = plans.filter(p => values[0]>=p.capital && values[1]>=p.directs && values[2]>=p.volume).at(-1);
  return p
    ? {name:p.name,rate:p.rate.toFixed(2)+'%',info:'Thresholds met in this demonstration. Real 24-hour activity, per-branch limits and available earnings are not verified.'}
    : {name:'NOT ELIGIBLE',rate:'—',info:'At least 10 USDT eligible own capital is required.'};
}
const fmt = n => Number(n).toLocaleString('en-US');
const links = [
  ['Home','#home'],['Invest','#plans'],['Markets','#markets'],
  ['Referrals','#referrals'],['Ranks','#ranks'],['Docs','#contract']
];

function Header() {
  const [open,setOpen] = useState(false);
  return <header className="header">
    <div className="container header-inner">
      <a href="#home" className="brand" onClick={()=>setOpen(false)}><span className="brand-symbol">N</span><span>Nexora <b>Markets</b></span></a>
      <span className="network"><span>⬡</span> BNB Smart Chain <small>PLANNED</small></span>
      <nav className={open?'nav expanded':'nav'} aria-label="Main navigation">
        {links.map(([name,href])=><a key={href} href={href} onClick={()=>setOpen(false)}>{name}</a>)}
      </nav>
      <span className="preview-mark">● PREVIEW</span>
      <button className="menu" type="button" aria-expanded={open} aria-label="Toggle navigation" onClick={()=>setOpen(!open)}>{open?'✕':'☰'}</button>
    </div>
  </header>;
}

function Hero(){
  return <section id="home" className="hero container">
    <div className="hero-copy">
      <div className="eyebrow">✧ &nbsp; THE NEXT GENERATION OF WEB3 MARKETS</div>
      <h1>Nexora <em>Markets.</em></h1>
      <h2>Beyond the ordinary.</h2>
      <p>Explore market intelligence, transparent protocol design and a new perspective on decentralized finance — in one carefully crafted experience.</p>
      <div className="actions"><a className="button primary" href="#markets">Explore Markets &nbsp; ↗</a><a className="button secondary" href="#plans">Explore Plans &nbsp; →</a></div>
      <div className="hero-notes"><span>● Public market sources</span><span>● No wallet transactions enabled</span></div>
    </div>
    <div className="hero-scene" aria-label="Decorative three-dimensional luminous Nexora token">
      <div className="orbit orbit-one"></div><div className="orbit orbit-two"></div>
      <div className="coin"><div className="coin-face"><span>N</span></div></div>
      <div className="pedestal"></div><div className="pedestal pedestal-two"></div>
    </div>
  </section>;
}

function OverviewRibbon(){
  return <div className="container ribbon">
    <div><span className="ribbon-icon">◈</span><small>MARKET INTELLIGENCE</small><b>Public sources</b></div>
    <div><span className="ribbon-icon violet-text">⬡</span><small>NETWORK</small><b>BNB Chain · planned</b></div>
    <div><span className="ribbon-icon mint-text">◇</span><small>CONTRACT</small><b>Not deployed</b></div>
    <div><span className="ribbon-icon pink-text">✧</span><small>SETTLEMENT</small><b>Disabled</b></div>
  </div>;
}

function PlanCards(){
  return <section id="plans" className="panel plan-panel">
    <div className="section-head"><div><span className="overline">01 / PROPOSED MODEL</span><h2>◈ &nbsp; Investment Plans</h2><p>Conditional daily payout caps based on eligible personal capital, active directs and group volume.</p></div><span className="chip">DESIGN PROPOSAL</span></div>
    <div className="plans">{plans.map(p=><article key={p.name} className={'plan '+p.accent}>
      <div className="crown">✦</div><h3>{p.name}</h3><strong className="rate">{p.rate.toFixed(2)}<span>%</span></strong><small className="rate-caption">Daily cap*</small>
      <div className="rule"></div><dl><div><dt>Active capital</dt><dd>{fmt(p.capital)}+ USDT</dd></div><div><dt>Active directs</dt><dd>{p.directs}</dd></div><div><dt>Group volume</dt><dd>{p.volume?fmt(p.volume)+'+ USDT':'None'}</dd></div></dl>
    </article>)}</div>
    <p className="disclaimer">* Hypothetical maximums, not guaranteed, accrued or withdrawable returns. Actual distributions require verified realized profit and adequate funds; they may be lower or zero. No new financial contract has launched.</p>
  </section>;
}

function ContractPanel(){
  return <section id="contract" className="panel side-panel">
    <div className="side-head"><h2>⛨ &nbsp; Contract Status</h2><span className="chip amber">● PRE-LAUNCH</span></div>
    <div className="detail-list">
      <div><span>⬡ &nbsp; Network</span><strong>BNB Smart Chain</strong></div>
      <div><span>₮ &nbsp; Planned asset</span><strong>USDT (BEP-20)</strong></div>
      <div><span>◇ &nbsp; New smart contract</span><strong>Not deployed</strong></div>
      <div><span>⊘ &nbsp; Deposits / payouts</span><strong>Disabled</strong></div>
    </div>
    <p className="muted">The new contract address, audited code and independent security review have not been published.</p>
  </section>;
}
function ProtocolPanel(){
  return <section className="panel side-panel"><div className="side-head"><h2>▥ &nbsp; Protocol Overview</h2></div>
    <div className="detail-list"><div><span>Network</span><strong>BNB Chain planned</strong></div><div><span>Profit distribution</span><strong>Awaiting verification</strong></div><div><span>Historical migration</span><strong>None</strong></div><div><span>Wallet transactions</span><strong>Off</strong></div></div>
    <p className="muted">Data from previous projects has not been imported. No performance history is represented as a verified Nexora return.</p>
  </section>;
}
function Markets(){
  return <section id="markets" className="panel info-panel"><span className="overline">02 / MARKET INTELLIGENCE</span><h2>Markets worth watching.</h2><p>Explore independent public market sources without connecting your wallet.</p>
    <div className="market-links"><a href="https://www.okx.com/markets/prices" target="_blank" rel="noreferrer"><span>↗</span><div><b>Spot markets</b><small>Public exchange prices</small></div><i>Explore ↗</i></a><a href="https://polymarket.com" target="_blank" rel="noreferrer"><span>◇</span><div><b>Prediction markets</b><small>Events and probabilities</small></div><i>Explore ↗</i></a></div>
  </section>;
}
function Referrals(){
  return <section id="referrals" className="panel info-panel"><span className="overline">03 / COMMUNITY</span><h2>Three-level referrals.</h2><p>Proposed commissions are based on actual settled investment profits — never on deposits alone.</p>
    <div className="referrals">{[15,7,3].map((pct,i)=><div key={i}><b>{pct}%</b><small>LEVEL {i+1}</small></div>)}</div>
    <p className="muted">Subject to an independently funded referral budget. No commissions on commissions, no guaranteed referral earnings.</p>
  </section>;
}
function RankCalculator(){
  const [capital,setCapital]=useState('2500');
  const [directs,setDirects]=useState('4');
  const [volume,setVolume]=useState('12500');
  const [answer,setAnswer]=useState(()=>calculateTier(2500,4,12500));
  function check(e){e.preventDefault();setAnswer(calculateTier(capital,directs,volume))}
  return <section id="ranks" className="panel calculator">
    <div className="section-head"><div><span className="overline">04 / MODEL SIMULATOR</span><h2>Explore your hypothetical tier.</h2><p>Sample eligibility rules only. This does not connect accounts, move funds or validate user networks.</p></div><span className="chip">INTERACTIVE PREVIEW</span></div>
    <div className="calculator-grid">
      <form onSubmit={check}><label>Own active capital (USDT)<input value={capital} onChange={e=>setCapital(e.target.value)} min="0" max="50000" type="number" inputMode="decimal"/></label><label>Active direct referrals<input value={directs} onChange={e=>setDirects(e.target.value)} min="0" type="number" step="1" inputMode="numeric"/></label><label>Three-level eligible group volume<input value={volume} onChange={e=>setVolume(e.target.value)} min="0" type="number" inputMode="decimal"/></label><button type="submit" className="button primary">Check tier ↗</button></form>
      <div className="answer" aria-live="polite"><small>YOUR HYPOTHETICAL TIER</small><h3>{answer.name}</h3><strong>{answer.rate}</strong><p>{answer.info}</p><small>Actual rules also require full 24-hour eligibility, a 50% volume limit per branch and sufficient realized profit.</small></div>
    </div>
  </section>;
}

export default function App(){
  return <><a href="#content" className="skip">Skip to content</a><Header/><main id="content"><Hero/><OverviewRibbon/><div className="container body-grid"><PlanCards/><aside className="side"><ContractPanel/><ProtocolPanel/></aside></div><div className="container secondary-grid"><Markets/><Referrals/></div><div className="container"><RankCalculator/></div></main>
  <footer className="container footer"><div className="brand"><span className="brand-symbol">N</span><span>NEXORA <b>MARKETS</b></span></div><p>Midnight Obsidian 3D · Frontend preview only. Not an active financial product, audited smart contract or guarantee of returns.</p><a href="#home">Back to top ↑</a></footer></>;
}
