// Called only by test-local-model2.py against its disposable loopback Anvil.
import assert from 'node:assert/strict';
import { readModel2Account, sendModel2TestnetAction } from '../src/model2Wallet.js';

const [endpoint, vault, token, account] = process.argv.slice(2);
const url = new URL(endpoint);
if (url.protocol !== 'http:' || url.hostname !== '127.0.0.1') {
  throw new Error('This test may only use a local Anvil node.');
}

const provider = {
  async request({ method, params = [] }) {
    if (method === 'eth_accounts') return [account];
    const response = await fetch(endpoint, {
      method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ jsonrpc:'2.0', id:1, method, params }),
    });
    const result = await response.json();
    if (result.error) throw new Error(result.error.message);
    return result.result;
  },
};

async function mined(hash) {
  for (let i=0;i<100;i++) {
    const receipt = await provider.request({method:'eth_getTransactionReceipt',params:[hash]});
    if (receipt) {
      assert.equal(BigInt(receipt.status), 1n, 'Local wallet transaction failed');
      return;
    }
    await new Promise(resolve => setTimeout(resolve, 50));
  }
  throw new Error('Local wallet transaction was not mined.');
}

const config = {vault,token,account};
await mined(await sendModel2TestnetAction(provider,config,'approve','1000'));
await mined(await sendModel2TestnetAction(provider,config,'deposit','1000'));
const result = await readModel2Account(provider,vault,token,account);
assert.deepEqual(result.snapshot,[1000n,1000n,800n,0n,200n].map(value=>value*10n**18n));
console.log('LOCAL_WALLET_E2E_OK: actual testnet UI encoding, approval, deposit and snapshot');
