'use client';

import WalletConnect from './components/WalletConnect';
import Dashboard from './components/Dashboard';
import { useEffect, useState } from 'react';

export default function Home() {
  const [connected, setConnected] = useState(false);
  const [userAddress, setUserAddress] = useState<string | null>(null);

  useEffect(() => {
    checkConnection();
  }, []);

  const checkConnection = async () => {
    if (typeof window !== 'undefined' && window.ethereum) {
      try {
        const accounts = await window.ethereum.request({
          method: 'eth_accounts',
        });
        if (accounts.length > 0) {
          setConnected(true);
          setUserAddress(accounts[0]);
        }
      } catch (error) {
        console.error('Error:', error);
      }
    }
  };

  return (
    <main className="min-h-screen py-12 px-4">
      <div className="max-w-7xl mx-auto">
        {connected ? (
          <Dashboard />
        ) : (
          <div className="flex flex-col items-center justify-center min-h-[60vh]">
            <WalletConnect />
          </div>
        )}
      </div>
    </main>
  );
}
