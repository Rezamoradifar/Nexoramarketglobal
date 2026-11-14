import test from 'node:test';
import assert from 'node:assert/strict';
import { parseTestTokenAmount, readModel2Account, sendModel2TestnetAction } from '../src/model2Wallet.js';

const vault = `0x${'1'.repeat(40)}`;
const token = `0x${'2'.repeat(40)}`;
const account = `0x${'3'.repeat(40)}`;
const other = `0x${'4'.repeat(40)}`;
const hash = `0x${'a'.repeat(64)}`;
const word = value => BigInt(value).toString(16).padStart(64, '0');
const symbol = `0x${word(32)}${word(7)}${Buffer.from('NXTTEST').toString('hex').padEnd(64, '0')}`;
const config = { vault, token, account };

function provider(options = {}) {
  const calls = [];
  let accountReads = 0;
  return {
    calls,
    async request(request) {
      calls.push(request);
      const { method, params = [] } = request;
      if (method === 'eth_chainId') return options.chain ?? '0x61';
      if (method === 'eth_accounts') {
        accountReads++;
        return [options.switchAfter && accountReads >= options.switchAfter ? other : account];
      }
      if (method === 'eth_getCode') return options.noCode ? '0x' : '0x6000';
      if (method === 'eth_sendTransaction') return hash;
      if (method === 'eth_call') {
        const data = params[0].data;
        if (data === '0x38d52e0f') return `0x${word(options.asset ?? token)}`;
        if (data === '0x313ce567') return `0x${word(options.decimals ?? 18)}`;
        if (data === '0x95d89b41') return options.symbol ?? symbol;
        if (data.startsWith('0x014a296f')) return `0x${[1000n,1000n,800n,5n,200n].map(x=>word(x*10n**18n)).join('')}`;
        if (data.startsWith('0xdd62ed3e')) return `0x${word(options.allowance ?? 0n)}`;
      }
      throw new Error(`Unexpected RPC method ${method}`);
    },
  };
}

test('test-token amounts use exact decimal arithmetic and reject invalid inputs', () => {
  assert.equal(parseTestTokenAmount('1000.000000000000000001'), 1000n * 10n**18n + 1n);
  for (const bad of ['0', '-1', '1e3', '1.1234567890123456789', 'Infinity', '']) {
    assert.throws(() => parseTestTokenAmount(bad));
  }
});

test('account snapshot is read only from matching testnet contracts', async () => {
  const p = provider();
  const result = await readModel2Account(p, vault, token, account);
  assert.equal(result.snapshot[2], 800n * 10n**18n);
  assert.equal(p.calls.some(call => call.method === 'eth_sendTransaction'), false);
});

test('mainnet, wrong token and missing bytecode block actions without sending', async () => {
  for (const options of [{ chain:'0x38' }, { asset:other }, { noCode:true }, { decimals:6 }, { symbol:'0x' }]) {
    const p = provider(options);
    await assert.rejects(sendModel2TestnetAction(p, config, 'approve', '10'));
    assert.equal(p.calls.some(call => call.method === 'eth_sendTransaction'), false);
  }
});

test('approval is exact and explicitly bound to testnet', async () => {
  const p = provider();
  assert.equal(await sendModel2TestnetAction(p, config, 'approve', '12.5'), hash);
  const tx = p.calls.find(call => call.method === 'eth_sendTransaction').params[0];
  assert.equal(tx.to, token);
  assert.equal(tx.from, account);
  assert.equal(tx.chainId, '0x61');
  assert.equal(tx.data, `0x095ea7b3${word(vault)}${word(125n*10n**17n)}`);
});

test('deposit requires a confirmed allowance and encodes the optional referrer', async () => {
  const insufficient = provider({ allowance:99n*10n**18n });
  await assert.rejects(sendModel2TestnetAction(insufficient, config, 'deposit', '100', other), /Approve/);
  assert.equal(insufficient.calls.some(call => call.method === 'eth_sendTransaction'), false);
  const enough = provider({ allowance:100n*10n**18n });
  await sendModel2TestnetAction(enough, config, 'deposit', '100', other);
  const tx = enough.calls.find(call => call.method === 'eth_sendTransaction').params[0];
  assert.equal(tx.to, vault);
  assert.equal(tx.data, `0x6e553f65${word(100n*10n**18n)}${word(other)}`);
});

test('wallet change before signing is rejected', async () => {
  const p = provider({ switchAfter:3 });
  await assert.rejects(sendModel2TestnetAction(p, config, 'claim'), /wallet changed/i);
  assert.equal(p.calls.some(call => call.method === 'eth_sendTransaction'), false);
});

test('reinvest, principal withdrawal and reward claim target only the configured vault', async () => {
  for (const [action, amount, expected] of [
    ['reinvest','4','0x24293f3d'], ['withdraw','2','0x658e28a4'], ['claim','','0x372500ab'],
  ]) {
    const p = provider();
    await sendModel2TestnetAction(p, config, action, amount);
    const tx = p.calls.find(call => call.method === 'eth_sendTransaction').params[0];
    assert.equal(tx.to, vault);
    assert.equal(tx.data.slice(0,10), expected);
  }
});
