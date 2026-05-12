import { useState, useCallback } from "react";
import { ethers } from "ethers";
import { DSC_ENGINE_ABI, ERC20_ABI } from "../abis/contracts";

const ADDRESSES = {
  DSC_ENGINE: "0x0165878A594ca255338adfa4d48449f69242Eb8F",
  DSC_COIN: "0x5FC8d32690cc91D4c39d9d3abcBD16989F875707",
  WETH: "0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512",
  WBTC: "0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0",
};

const SUPPORTED_TOKENS = [
  { symbol: "WETH", address: ADDRESSES.WETH, decimals: 18, icon: "Ξ" },
  { symbol: "WBTC", address: ADDRESSES.WBTC, decimals: 8, icon: "₿" },
];

const EMPTY_INFO = {
  dscMinted: 0, collateralValueUsd: 0, healthFactor: "0",
  wethBalance: 0, wbtcBalance: 0, wethCollateral: 0, wbtcCollateral: 0, dscBalance: 0,
};

export function useProtocol() {
  const [state, setState] = useState({
    signer: null, address: null, chainId: null, engine: null,
    loading: false, txPending: false, error: null,
    accountInfo: EMPTY_INFO,
  });

  const fetchData = useCallback(async (signer, address, engine) => {
    try {
      const wethC = new ethers.Contract(ADDRESSES.WETH, ERC20_ABI, signer);
      const wbtcC = new ethers.Contract(ADDRESSES.WBTC, ERC20_ABI, signer);
      const dscC = new ethers.Contract(ADDRESSES.DSC_COIN, ERC20_ABI, signer);

      const [info, hf, wethBal, wbtcBal, wethCol, wbtcCol, dscBal] = await Promise.all([
        engine.getAccountInformation(address),
        engine.getHealthFactor(address),
        wethC.balanceOf(address),
        wbtcC.balanceOf(address),
        engine.getCollateralBalanceOfUser(address, ADDRESSES.WETH),
        engine.getCollateralBalanceOfUser(address, ADDRESSES.WBTC),
        dscC.balanceOf(address),
      ]);

      const hfBig = BigInt(hf.toString());
      const hfVal = hfBig > BigInt("100000000000000000000")
        ? "∞" : (Number(hfBig) / 1e18).toFixed(2);

      return {
        dscMinted: Number(ethers.formatEther(info[0])),
        collateralValueUsd: Number(ethers.formatEther(info[1])),
        healthFactor: hfVal,
        wethBalance: Number(ethers.formatEther(wethBal)),
        wbtcBalance: Number(ethers.formatUnits(wbtcBal, 8)),
        wethCollateral: Number(ethers.formatEther(wethCol)),
        wbtcCollateral: Number(ethers.formatUnits(wbtcCol, 8)),
        dscBalance: Number(ethers.formatEther(dscBal)),
      };
    } catch (e) {
      console.error("fetchData error:", e);
      return null;
    }
  }, []);

  const connect = useCallback(async () => {
    if (!window.ethereum) {
      setState(s => ({ ...s, error: "MetaMask not detected." }));
      return;
    }
    setState(s => ({ ...s, loading: true, error: null }));
    try {
      try {
        await window.ethereum.request({
          method: "wallet_switchEthereumChain",
          params: [{ chainId: "0x7a69" }],
        });
      } catch (_) { }

      const provider = new ethers.BrowserProvider(window.ethereum);
      await provider.send("eth_requestAccounts", []);
      const signer = await provider.getSigner();
      const address = await signer.getAddress();
      const network = await provider.getNetwork();
      const engine = new ethers.Contract(ADDRESSES.DSC_ENGINE, DSC_ENGINE_ABI, signer);

      const accountInfo = await fetchData(signer, address, engine);

      setState(s => ({
        ...s, signer, address, engine,
        chainId: Number(network.chainId),
        loading: false,
        accountInfo: accountInfo || EMPTY_INFO,
      }));
    } catch (err) {
      setState(s => ({ ...s, loading: false, error: err.message }));
    }
  }, [fetchData]);

  const refreshAccountInfo = useCallback(async () => {
    const { signer, address, engine } = state;
    if (!signer || !address || !engine) return;
    const accountInfo = await fetchData(signer, address, engine);
    if (accountInfo) setState(s => ({ ...s, accountInfo }));
  }, [state, fetchData]);

  const withTx = useCallback(async (txFn) => {
    setState(s => ({ ...s, txPending: true, error: null }));
    try {
      const tx = await txFn();
      await tx.wait();
      const { signer, address, engine } = state;
      const accountInfo = await fetchData(signer, address, engine);
      setState(s => ({ ...s, txPending: false, accountInfo: accountInfo || s.accountInfo }));
      return { success: true, hash: tx.hash };
    } catch (err) {
      const msg = err?.reason || err?.message || "Transaction failed";
      setState(s => ({ ...s, txPending: false, error: msg }));
      return { success: false, error: msg };
    }
  }, [state, fetchData]);

  const approveToken = useCallback(async (tokenAddress, amount) => {
    const token = new ethers.Contract(tokenAddress, ERC20_ABI, state.signer);
    return withTx(() => token.approve(ADDRESSES.DSC_ENGINE, amount));
  }, [state.signer, withTx]);

  const depositAndMint = useCallback(async (tokenSymbol, collateralAmount, dscAmount) => {
    const token = SUPPORTED_TOKENS.find(t => t.symbol === tokenSymbol);
    if (!token) return { success: false, error: "Unknown token" };
    const collBN = ethers.parseUnits(String(collateralAmount), token.decimals);
    const dscBN = ethers.parseEther(String(dscAmount));
    const approved = await approveToken(token.address, collBN);
    if (!approved.success) return approved;
    return withTx(() => state.engine.depositCollateralAndMintDsc(token.address, collBN, dscBN));
  }, [state.engine, approveToken, withTx]);

  const redeemAndBurn = useCallback(async (tokenSymbol, collateralAmount, dscAmount) => {
    const token = SUPPORTED_TOKENS.find(t => t.symbol === tokenSymbol);
    if (!token) return { success: false, error: "Unknown token" };
    const collBN = ethers.parseUnits(String(collateralAmount), token.decimals);
    const dscBN = ethers.parseEther(String(dscAmount));
    const dscC = new ethers.Contract(ADDRESSES.DSC_COIN, ERC20_ABI, state.signer);
    const approved = await withTx(() => dscC.approve(ADDRESSES.DSC_ENGINE, dscBN));
    if (!approved.success) return approved;
    return withTx(() => state.engine.redeemCollateralForDsc(token.address, collBN, dscBN));
  }, [state.engine, state.signer, withTx]);

  const liquidate = useCallback(async (tokenSymbol, userAddress, debtAmount) => {
    const token = SUPPORTED_TOKENS.find(t => t.symbol === tokenSymbol);
    if (!token) return { success: false, error: "Unknown token" };
    const debtBN = ethers.parseEther(String(debtAmount));
    const dscC = new ethers.Contract(ADDRESSES.DSC_COIN, ERC20_ABI, state.signer);
    const approved = await withTx(() => dscC.approve(ADDRESSES.DSC_ENGINE, debtBN));
    if (!approved.success) return approved;
    return withTx(() => state.engine.liquidate(token.address, userAddress, debtBN));
  }, [state.engine, state.signer, withTx]);

  return {
    connect,
    address: state.address,
    chainId: state.chainId,
    loading: state.loading,
    txPending: state.txPending,
    error: state.error,
    isConnected: !!state.address,
    accountInfo: state.accountInfo,
    supportedTokens: SUPPORTED_TOKENS,
    addresses: ADDRESSES,
    refreshAccountInfo,
    depositAndMint,
    redeemAndBurn,
    liquidate,
  };
}