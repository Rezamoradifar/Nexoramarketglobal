import { useState } from 'react';
import './Model2Preview.css';

// This module is TESTNET-ONLY and read-only, pending independent audit.
const vaultAddress = (import.meta.env.VITE_NEXORA_MODEL2_TESTNET_VAULT || '').trim();
const deployedAddressConfigured = /^0x[0-9a-fA-F]{40}$/.test(vaultAddress);
const SNAPSHOT_SELECTOR = '0x014a296f'; // cast sig 'accountSnapshot(address)'
const TOKEN_UNIT = 10n ** 18n;
const TIERS = [
  { name:'VIP 1', bps:100, needs:'Minimum 10 USDT gross capital' },
  { name:'VIP 2', bps:125, needs:'500 USDT + 2 active directs + team requirements' },
  { name:'VIP 3', bps:150, needs:'2,500 USDT + 4 active directs + team requirements' },
  { name:'VIP 4', bps:200, needs:'10,000 USDT + 6 active directs + team requirements' },
  { name:'VIP 5', bps:250, needs:'25,000 USDT + 10 active directs + team requirements' },
];
const display = value => Number(value || 0).toLocaleString('en-US',{maximumFractionDigits:2});
function displayToken(raw){
  const whole=raw/TOKEN_UNIT;
  const cents=((raw%TOKEN_UNIT)*100n/TOKEN_UNIT).toString().padStart(2,'0');
  return whole.toLocaleString('en-US')+'.'+cents;
}
function parseSnapshot(hex){
  if(!/^0x(?:[0-9a-fA-F]{64}){5}$/.test(hex))
    throw new Error('Invalid account data returned by the configured testnet contract.');
  return hex.slice(2).match(/.{64}/g).map(x=>BigInt('0x'+x));
}

export default function Model2Preview(){
  const [grossInput,setGrossInput]=useState('1000');
  const [tierNumber,setTierNumber]=useState(0);
  const [wallet,setWallet]=useState({status:'idle',message:'',account:'',snapshot:null});
  const selected=TIERS[tierNumber];
  const num=Number(grossInput);
  const gross=Number.isFinite(num)?Math.max(0,Math.min(50000,num)):0;
  const net=gross*.8, owner=gross*.06, each=gross*.014;
  const ceiling=gross*selected.bps/10000;

  async function readAccount(){
    if(!deployedAddressConfigured)return;
    if(typeof window==='undefined' || !window.ethereum?.request){
      setWallet({status:'error',message:'EIP-1193 wallet not detected.',account:'',snapshot:null});
      return;
    }
    setWallet({status:'loading',message:'Reading TESTNET state only…',account:'',snapshot:null});
    try{
      const provider=window.ethereum;
      const chainId=await provider.request({method:'eth_chainId'});
      if(Number.parseInt(chainId,16)!==97)
        throw new Error('Switch to BNB TESTNET (chain ID 97) in your wallet.');
      const accounts=await provider.request({method:'eth_requestAccounts'});
      const account=accounts?.[0];
      if(!/^0x[0-9a-fA-F]{40}$/.test(account||''))
        throw new Error('No valid public wallet address selected.');
      const code=await provider.request({method:'eth_getCode',params:[vaultAddress,'latest']});
      if(!code || code==='0x' || code==='0x0')
        throw new Error('Configured address has no deployed contract on testnet.');
      const param=account.slice(2).toLowerCase().padStart(64,'0');
      const data=await provider.request({
        method:'eth_call',
        params:[{to:vaultAddress,data:SNAPSHOT_SELECTOR+param},'latest'],
      });
      const snapshot=parseSnapshot(data);
      setWallet({status:'success',message:'BNB Testnet data loaded. No transactions were sent.',account,snapshot});
    }catch(error){
      setWallet({status:'error',message:error?.message||'Testnet account read failed.',account:'',snapshot:null});
    }
  }

  return <section className="model2-preview wide" id="model2-preview" aria-labelledby="model2-title">
    <div className="model2-intro">
      <div>
        <span className="model2-kicker">NEXORA · MODEL 2 · AUDIT-PENDING TESTNET PREVIEW</span>
        <h2 id="model2-title">Your deposit history and your actual principal.</h2>
        <p>Transparency by design: the full transaction remains in your deposit history, while the actual withdrawable principal is the net amount after the disclosed upfront allocation.</p>
      </div>
      <span className="model2-preview-status">Illustration · Not a live account</span>
    </div>
    <div className="model2-layout">
      <div className="model2-main">
        <label htmlFor="model2-gross">Example gross deposit (USDT)</label>
        <input id="model2-gross" type="number" min="10" max="50000" step="10"
          value={grossInput} onChange={e=>setGrossInput(e.target.value)}/>
        <div className="model2-gross"><span>Historical gross deposited</span><strong>{display(gross)} USDT</strong></div>
        <div className="model2-track" aria-hidden="true">
          <span className="model2-principal-track"/><span className="model2-owner-track"/><span className="model2-company-track"/>
        </div>
        <dl className="model2-ledger">
          <div><dt>Actual net user principal · 80%</dt><dd>{display(net)} USDT</dd></div>
          <div><dt>Owner allocation · 6%</dt><dd>{display(owner)} USDT</dd></div>
          <div><dt>Each of ten company wallets · 1.4%</dt><dd>{display(each)} USDT</dd></div>
          <div className="model2-total"><dt>Total originally deposited · 100%</dt><dd>{display(gross)} USDT</dd></div>
        </dl>
        <p className="model2-disclosure"><strong>Financial disclosure:</strong> {display(gross)} USDT is a historical deposit record, NOT a guaranteed redeemable balance. Only {display(net)} USDT is booked as principal, before withdrawals. All numbers in this card are illustrative.</p>
      </div>
      <div className="model2-side">
        <div className="model2-side-card">
          <label htmlFor="model2-tier">Illustrative VIP ceiling</label>
          <select id="model2-tier" value={tierNumber} onChange={e=>setTierNumber(Number(e.target.value))}>
            {TIERS.map((t,i)=><option key={t.name} value={i}>{t.name} · {t.bps/100}% max</option>)}
          </select>
          <p>{selected.needs}</p>
          <div className="model2-ceiling"><span>Maximum conditional daily allocation</span><strong>{display(ceiling)} USDT</strong></div>
          <p>Calculated from an illustrative gross plan basis. Only actual fully funded realized earnings may be allocated; payments can be zero.</p>
        </div>
        <div className="model2-side-card">
          <h3>Withdrawal &amp; Reinvest terms</h3>
          <dl>
            <div><dt>Lock</dt><dd>90 days per tranche</dd></div>
            <div><dt>Daily withdrawal cap</dt><dd>20% gross external deposits</dd></div>
            <div><dt>Withdrawal fee</dt><dd>0%</dd></div>
            <div><dt>Reinvest</dt><dd>80% net principal / 20% upfront allocation</dd></div>
          </dl>
          <p>Daily limits never create funds beyond mature, actually backed balances.</p>
        </div>
      </div>
    </div>
    <div className="model2-testnet">
      <div>
        <h3>Read-only wallet viewer · BNB TESTNET</h3>
        <p>When a separately audited testnet contract address is configured, you may choose to share a public wallet address to read actual testnet balances. No approvals, signatures or transfers.</p>
      </div>
      <button type="button" disabled={!deployedAddressConfigured || wallet.status==='loading'} onClick={readAccount}>
        {wallet.status==='loading'?'Reading…':deployedAddressConfigured?'Read my testnet account':'Awaiting testnet deployment'}
      </button>
      {wallet.message&&<p role="status" className="model2-wallet-message">{wallet.message}</p>}
      {wallet.status==='success'&&wallet.snapshot&&
        <div className="model2-testnet-data">
          <p>TESTNET · {wallet.account.slice(0,6)}…{wallet.account.slice(-4)}</p>
          {[
            ['Gross deposit history',wallet.snapshot[0]],
            ['Open gross plan reference',wallet.snapshot[1]],
            ['Net backed principal',wallet.snapshot[2]],
            ['Funded credited rewards',wallet.snapshot[3]],
            ['24h remaining withdrawal allowance',wallet.snapshot[4]],
          ].map(([label,value])=><div key={label}><span>{label}</span><strong>{displayToken(value)} test tokens</strong></div>)}
        </div>}
    </div>
  </section>;
}
