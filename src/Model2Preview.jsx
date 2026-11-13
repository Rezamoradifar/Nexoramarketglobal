import { useEffect, useState } from 'react';
import './Model2Preview.css';
import { isConfiguredAddress, readModel2Account, sendModel2TestnetAction } from './model2Wallet.js';

// The optional transaction panel is testnet-only and remains unpublished.
const vaultAddress = (import.meta.env.VITE_NEXORA_MODEL2_TESTNET_VAULT || '').trim();
const tokenAddress = (import.meta.env.VITE_NEXORA_MODEL2_TESTNET_TOKEN || '').trim();
const deployedAddressConfigured = isConfiguredAddress(vaultAddress) && isConfiguredAddress(tokenAddress);
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
export default function Model2Preview(){
  const [grossInput,setGrossInput]=useState('1000');
  const [tierNumber,setTierNumber]=useState(0);
  const [wallet,setWallet]=useState({status:'idle',message:'',account:'',snapshot:null});
  const [depositAmount,setDepositAmount]=useState('');
  const [referrer,setReferrer]=useState('');
  const [reinvestAmount,setReinvestAmount]=useState('');
  const [withdrawAmount,setWithdrawAmount]=useState('');
  const [transaction,setTransaction]=useState({busy:false,hash:'',message:''});
  const selected=TIERS[tierNumber];
  const num=Number(grossInput);
  const gross=Number.isFinite(num)?Math.max(0,Math.min(50000,num)):0;
  const net=gross*.8, owner=gross*.06, each=gross*.014;
  const ceiling=gross*selected.bps/10000;

  useEffect(()=>{
    const provider=window.ethereum;
    if(!provider?.on)return undefined;
    const reset=()=>{
      setWallet({status:'idle',message:'Wallet or network changed. Reconnect to continue.',account:'',snapshot:null});
      setTransaction({busy:false,hash:'',message:''});
    };
    provider.on('accountsChanged',reset);
    provider.on('chainChanged',reset);
    return ()=>{
      provider.removeListener?.('accountsChanged',reset);
      provider.removeListener?.('chainChanged',reset);
    };
  },[]);

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
      if(typeof chainId!=='string'||!/^0x[0-9a-f]+$/i.test(chainId)||BigInt(chainId)!==97n)
        throw new Error('Switch to BNB TESTNET (chain ID 97) in your wallet.');
      const accounts=await provider.request({method:'eth_requestAccounts'});
      const account=accounts?.[0];
      if(!/^0x[0-9a-fA-F]{40}$/.test(account||''))
        throw new Error('No valid public wallet address selected.');
      const {snapshot}=await readModel2Account(provider,vaultAddress,tokenAddress,account);
      setWallet({status:'success',message:'BNB Testnet data loaded. No transactions were sent.',account,snapshot});
    }catch(error){
      setWallet({status:'error',message:error?.message||'Testnet account read failed.',account:'',snapshot:null});
    }
  }

  async function runAction(action,amount='',sponsor=''){
    if(wallet.status!=='success'||transaction.busy)return;
    setTransaction({busy:true,hash:'',message:'Confirm this testnet action in your wallet.'});
    try{
      const hash=await sendModel2TestnetAction(window.ethereum,
        {vault:vaultAddress,token:tokenAddress,account:wallet.account},action,amount,sponsor);
      setTransaction({busy:false,hash,message:'Submitted to BNB Testnet. Check confirmation before continuing.'});
    }catch(error){
      setTransaction({busy:false,hash:'',message:error?.message||'Testnet transaction was not submitted.'});
    }
  }

  async function checkTransaction(){
    if(!transaction.hash||transaction.busy)return;
    const hash=transaction.hash;
    setTransaction({busy:true,hash,message:'Checking transaction confirmation…'});
    try{
      const {account,snapshot}=await readModel2Account(window.ethereum,vaultAddress,tokenAddress,wallet.account);
      const receipt=await window.ethereum.request({method:'eth_getTransactionReceipt',params:[hash]});
      if(!receipt){setTransaction({busy:false,hash,message:'Still pending on BNB Testnet.'});return;}
      if(typeof receipt.status!=='string'||BigInt(receipt.status)!==1n){
        setTransaction({busy:false,hash,message:'Transaction failed on BNB Testnet.'});return;
      }
      setWallet({status:'success',message:'Testnet account refreshed.',account,snapshot});
      setTransaction({busy:false,hash,message:'Confirmed on BNB Testnet.'});
    }catch(error){
      setTransaction({busy:false,hash,message:error?.message||'Could not check the transaction.'});
    }
  }

  return <section className="model2-preview wide" id="model2-preview" aria-labelledby="model2-title">
    <div className="model2-intro">
      <div>
        <span className="model2-kicker">NEXORA · MODEL 2 · AUDIT-PENDING TESTNET PREVIEW</span>
        <h2 id="model2-title">Your deposit history and your actual principal.</h2>
        <p>Transparency by design: the full transaction remains in your deposit history. Net principal is subject to the disclosed upfront allocation, maturity and withdrawal limits.</p>
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
            <div><dt>Principal lock</dt><dd>90 days per deposit or reinvest tranche</dd></div>
            <div><dt>Reward claims</dt><dd>90 days from first deposit</dd></div>
            <div><dt>Daily withdrawal cap</dt><dd>20% gross external deposits</dd></div>
            <div><dt>Withdrawal fee</dt><dd>0%</dd></div>
            <div><dt>Reinvest</dt><dd>80% net principal / 20% upfront allocation</dd></div>
          </dl>
          <p>Principal and reward claims share the 24-hour limit. Reinvest does not increase the limit, and credited rewards require a funded reserve.</p>
        </div>
      </div>
    </div>
    <div className="model2-testnet">
      <div>
        <h3>Test account · BNB TESTNET only</h3>
        <p>This unpublished test panel uses NXTTEST, a token with no value. Each action requires a separate wallet confirmation. It cannot be used for real USDT or mainnet.</p>
      </div>
      <button type="button" disabled={!deployedAddressConfigured || wallet.status==='loading'} onClick={readAccount}>
        {wallet.status==='loading'?'Reading…':deployedAddressConfigured?'Connect & read test account':'Awaiting testnet deployment'}
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
          <p>The remaining limit is not a withdrawable balance. Maturity, funded balances and other contract rules still apply.</p>
        </div>}
      {wallet.status==='success'&&wallet.snapshot&&
        <div className="model2-actions">
          <div className="model2-actions-heading"><h3>Practice with test tokens</h3><span>Chain 97 · NXTTEST only</span></div>
          <p>Deposits and reinvestment allocate 20% upfront; 80% becomes net principal. The full gross amount is a plan reference, not a withdrawable balance.</p>
          <div className="model2-action-grid">
            <div className="model2-action-card">
              <label htmlFor="test-deposit">Test deposit amount</label>
              <input id="test-deposit" inputMode="decimal" value={depositAmount} onChange={e=>setDepositAmount(e.target.value)} placeholder="e.g. 1000"/>
              <label htmlFor="test-referrer">Referrer address · optional on first deposit</label>
              <input id="test-referrer" value={referrer} onChange={e=>setReferrer(e.target.value)} placeholder="0x…" autoComplete="off"/>
              <div className="model2-action-buttons">
                <button disabled={transaction.busy} onClick={()=>runAction('approve',depositAmount)}>1. Approve exact amount</button>
                <button disabled={transaction.busy} onClick={()=>runAction('deposit',depositAmount,referrer)}>2. Deposit</button>
              </div>
              <p>Wait for the approval transaction to confirm before depositing.</p>
            </div>
            <div className="model2-action-card">
              <label htmlFor="test-reinvest">Reinvest credited rewards</label>
              <input id="test-reinvest" inputMode="decimal" value={reinvestAmount} onChange={e=>setReinvestAmount(e.target.value)} placeholder="Amount"/>
              <button disabled={transaction.busy} onClick={()=>runAction('reinvest',reinvestAmount)}>Reinvest test rewards</button>
              <p>A new 90-day principal lock and the 20% allocation apply.</p>
            </div>
            <div className="model2-action-card">
              <label htmlFor="test-withdraw">Withdraw matured principal</label>
              <input id="test-withdraw" inputMode="decimal" value={withdrawAmount} onChange={e=>setWithdrawAmount(e.target.value)} placeholder="Amount"/>
              <div className="model2-action-buttons">
                <button disabled={transaction.busy} onClick={()=>runAction('withdraw',withdrawAmount)}>Withdraw test principal</button>
                <button disabled={transaction.busy} onClick={()=>runAction('claim')}>Claim test rewards</button>
              </div>
              <p>Principal and reward claims share the 24-hour limit and must meet their maturity rules.</p>
            </div>
          </div>
          {transaction.message&&<p role="status" className="model2-transaction-message">{transaction.message}</p>}
          {transaction.hash&&<div className="model2-transaction-link"><a href={`https://testnet.bscscan.com/tx/${transaction.hash}`} target="_blank" rel="noreferrer">View testnet transaction ↗</a><button disabled={transaction.busy} onClick={checkTransaction}>Check confirmation</button></div>}
        </div>}
    </div>
  </section>;
}
