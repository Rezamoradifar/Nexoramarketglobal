// TESTNET ONLY. This module signs nothing by itself; the user confirms each
// transaction in their wallet. No real token or mainnet operation is supported.
const TESTNET_CHAIN_ID = 97;
const UINT256_MAX = (1n << 256n) - 1n;
const ZERO_ADDRESS = `0x${'0'.repeat(40)}`;
const SELECTORS = {
  asset: '0x38d52e0f',
  decimals: '0x313ce567',
  symbol: '0x95d89b41',
  snapshot: '0x014a296f',
  allowance: '0xdd62ed3e',
  approve: '0x095ea7b3',
  deposit: '0x6e553f65',
  reinvest: '0x24293f3d',
  withdraw: '0x658e28a4',
  claim: '0x372500ab',
};

export function isConfiguredAddress(value) {
  return /^0x[0-9a-fA-F]{40}$/.test(value || '') && value.toLowerCase() !== ZERO_ADDRESS;
}

export function parseTestTokenAmount(value) {
  const text = String(value).trim();
  if (text.length > 80 || !/^(?:0|[1-9]\d*)(?:\.\d{1,18})?$/.test(text)) {
    throw new Error('Enter a positive test-token amount with at most 18 decimals.');
  }
  const [whole, fraction = ''] = text.split('.');
  const amount = BigInt(whole) * 10n ** 18n + BigInt((fraction + '0'.repeat(18)).slice(0, 18));
  if (amount === 0n || amount > UINT256_MAX) throw new Error('Enter a valid positive test-token amount.');
  return amount;
}

function word(value) {
  return BigInt(value).toString(16).padStart(64, '0');
}

function encodeAddress(address) {
  if (!/^0x[0-9a-fA-F]{40}$/.test(address || '')) throw new Error('Enter a valid wallet address.');
  return address.slice(2).toLowerCase().padStart(64, '0');
}

function encodeUint(value) {
  if (value < 0n || value > UINT256_MAX) throw new Error('Invalid token amount.');
  return word(value);
}

function decodeWords(hex, count) {
  if (typeof hex !== 'string' || !new RegExp(`^0x[0-9a-fA-F]{${count * 64}}$`).test(hex)) {
    throw new Error('Invalid data returned by the configured testnet contract.');
  }
  return hex.slice(2).match(/.{64}/g).map(part => BigInt(`0x${part}`));
}

function decodeSymbol(hex) {
  if (typeof hex !== 'string' || !/^0x[0-9a-fA-F]+$/.test(hex) || hex.length < 130) {
    throw new Error('Invalid test-token symbol response.');
  }
  const body = hex.slice(2);
  const offset = Number(BigInt(`0x${body.slice(0, 64)}`));
  if (!Number.isSafeInteger(offset) || offset !== 32) throw new Error('Invalid test-token symbol response.');
  const length = Number(BigInt(`0x${body.slice(64, 128)}`));
  if (!Number.isSafeInteger(length) || length > 32 || body.length < 128 + length * 2) {
    throw new Error('Invalid test-token symbol response.');
  }
  const bytes = body.slice(128, 128 + length * 2).match(/../g) || [];
  return String.fromCharCode(...bytes.map(byte => parseInt(byte, 16)));
}

async function requireWallet(provider, expectedAccount) {
  const chainId = await provider.request({ method: 'eth_chainId' });
  if (typeof chainId !== 'string' || !/^0x[0-9a-f]+$/i.test(chainId) || BigInt(chainId) !== 97n) {
    throw new Error('Switch your wallet to BNB TESTNET (chain ID 97).');
  }
  const accounts = await provider.request({ method: 'eth_accounts' });
  const selected = accounts?.[0];
  if (!isConfiguredAddress(selected) || (expectedAccount && selected.toLowerCase() !== expectedAccount.toLowerCase())) {
    throw new Error('The selected wallet changed. Reconnect before continuing.');
  }
  return selected;
}

async function call(provider, address, data) {
  return provider.request({ method: 'eth_call', params: [{ to: address, data }, 'latest'] });
}

export async function verifyTestnetSetup(provider, vault, token, expectedAccount) {
  if (!provider?.request || !isConfiguredAddress(vault) || !isConfiguredAddress(token) ||
      vault.toLowerCase() === token.toLowerCase()) {
    throw new Error('Verified testnet vault and test-token addresses are required.');
  }
  const account = await requireWallet(provider, expectedAccount);
  for (const address of [vault, token]) {
    const code = await provider.request({ method: 'eth_getCode', params: [address, 'latest'] });
    if (typeof code !== 'string' || !/^0x[0-9a-f]+$/i.test(code) || /^0x0*$/i.test(code)) {
      throw new Error('A configured testnet address does not contain contract code.');
    }
  }
  const [asset] = decodeWords(await call(provider, vault, SELECTORS.asset), 1);
  if (asset !== BigInt(token)) throw new Error('Vault token does not match the configured test token.');
  const [decimals] = decodeWords(await call(provider, token, SELECTORS.decimals), 1);
  if (decimals !== 18n || decodeSymbol(await call(provider, token, SELECTORS.symbol)) !== 'NXTTEST') {
    throw new Error('Configured token is not the expected 18-decimal Nexora test token.');
  }
  await requireWallet(provider, account);
  return account;
}

export async function readModel2Account(provider, vault, token, account) {
  const selected = await verifyTestnetSetup(provider, vault, token, account);
  const snapshot = decodeWords(await call(provider, vault, SELECTORS.snapshot + encodeAddress(selected)), 5);
  await requireWallet(provider, selected);
  return { account: selected, snapshot };
}

export async function sendModel2TestnetAction(provider, config, action, amountText = '', referrer = '') {
  const { vault, token, account } = config;
  const selected = await verifyTestnetSetup(provider, vault, token, account);
  let target = vault;
  let payload;
  if (action === 'approve' || action === 'deposit') {
    const amount = parseTestTokenAmount(amountText);
    if (action === 'approve') {
      target = token;
      payload = SELECTORS.approve + encodeAddress(vault) + encodeUint(amount);
    } else {
      const [allowance] = decodeWords(await call(provider, token,
        SELECTORS.allowance + encodeAddress(selected) + encodeAddress(vault)), 1);
      if (allowance < amount) throw new Error('Approve this exact amount and wait for confirmation first.');
      const sponsor = referrer.trim() || ZERO_ADDRESS;
      payload = SELECTORS.deposit + encodeUint(amount) + encodeAddress(sponsor);
    }
  } else if (action === 'reinvest' || action === 'withdraw') {
    payload = SELECTORS[action] + encodeUint(parseTestTokenAmount(amountText));
  } else if (action === 'claim') {
    payload = SELECTORS.claim;
  } else {
    throw new Error('Unknown testnet action.');
  }

  // Check again immediately before opening the wallet confirmation.
  await requireWallet(provider, selected);
  const hash = await provider.request({
    method: 'eth_sendTransaction',
    params: [{ from: selected, to: target, data: payload, chainId: `0x${TESTNET_CHAIN_ID.toString(16)}` }],
  });
  if (!/^0x[0-9a-fA-F]{64}$/.test(hash || '')) throw new Error('Wallet did not return a valid transaction hash.');
  return hash;
}
