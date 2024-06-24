import React, { useState } from 'react';
import { ethers } from 'ethers';
import MultiSigNFTEscrowABI from './MultiSigNFTEscrow.json'; // Ensure ABI JSON file is in the src directory
import Button from 'react-bootstrap/Button';
import 'bootstrap/dist/css/bootstrap.min.css';

const CONTRACT_ADDRESS = "0x6f1D14C60B59e70f1b70d6d58419D757Cf456DeE"; // Replace with your actual contract address

function App() {
  const [signer, setSigner] = useState(null);
  const [contract, setContract] = useState(null);
  const [tokenId, setTokenId] = useState('');
  const [bellsInside, setBellsInside] = useState('');
  const [custMessHash, setCustMessHash] = useState('');
  const [apiMessHash, setApiMessHash] = useState('');

  const connectWallet = async () => {
    if (window.ethereum) {
      const provider = new ethers.providers.Web3Provider(window.ethereum);
      await provider.send("eth_requestAccounts", []);
      const signer = provider.getSigner();
      
      // Parse the ABI
      const parsedABI = JSON.parse(MultiSigNFTEscrowABI.result);

      const contract = new ethers.Contract(CONTRACT_ADDRESS, parsedABI, signer);

      setSigner(signer);
      setContract(contract);
    } else {
      console.log('Install Metamask');
    }
  };

  const signData = async (message) => {
    try {
      if (!signer) {
        console.error("No signer available");
        return null;
      }
      const messageHash = ethers.utils.keccak256(ethers.utils.toUtf8Bytes(message));
      const signature = await signer.signMessage(ethers.utils.arrayify(messageHash));
      return { signature, messageHash };
    } catch (error) {
      console.error("Error signing message:", error);
      return null;
    }
  };

  const pawnNFT = async () => {
    try {
      if (!signer) {
        console.error("No signer available");
        return;
      }

      // Ensure all values are set
      if (!tokenId || !bellsInside) {
        console.error("Token ID and Bells Inside fields must be filled");
        return;
      }

      const message = `${tokenId}-${bellsInside}`;
      
      // Sign the data
      const { signature: signatureCust, messageHash: custMessHash } = await signData(message);
      const { signature: signatureApi, messageHash: apiMessHash } = await signData(message);

      if (!signatureCust || !signatureApi) {
        console.error("Signing failed");
        return;
      }

      const { v: vCust, r: rCust, s: sCust } = ethers.utils.splitSignature(signatureCust);
      const { v: vApi, r: rApi, s: sApi } = ethers.utils.splitSignature(signatureApi);

      console.log("Debug Values:");
      console.log("tokenId:", tokenId);
      console.log("bellsInside:", bellsInside);
      console.log("custMessHash:", custMessHash);
      console.log("apiMessHash:", apiMessHash);
      console.log("vCust:", vCust);
      console.log("rCust:", rCust);
      console.log("sCust:", sCust);
      console.log("vApi:", vApi);
      console.log("rApi:", rApi);
      console.log("sApi:", sApi);

      const tx = await contract.pawn(
        tokenId,
        bellsInside,
        custMessHash,
        apiMessHash,
        vCust,
        rCust,
        sCust,
        vApi,
        rApi,
        sApi
      );
      await tx.wait();
      console.log('Transaction Successful');
    } catch (error) {
      console.error('Transaction Failed', error);
    }
  };

  return (
    <body style={{backgroundColor: 'black', height: '100vh'}}>
      <div>
        <button onClick={connectWallet}>Connect Wallet</button>
        <div style={{border: 'solid', borderWidth: '1px', borderColor: 'white', borderRadius: '20px', height: '40vh', width: '50vw',
          position: 'fixed', left: '25vw', top: '25vh'
        }}>
          <input
            style={{position: 'relative', top: '10vh', left: '5vw', width: '40vw'}}
            type="text"
            placeholder="Token ID"
            value={tokenId}
            onChange={(e) => {setTokenId(e.target.value); setApiMessHash(e.target.value); setCustMessHash(e.target.value)}}
          />
          <input
             style={{position: 'relative', top: '18vh', left: '-20vw'}}
            type="text"
            placeholder="Bells Inside"
            value={bellsInside}
            onChange={(e) => setBellsInside(e.target.value)}
          />
          <Button variant="warning" size="lg" onClick={pawnNFT} style={{borderRadius: '50px', position: 'relative', top: '25vh', left: '20vw', width: '10vw'}}>Pawn NFT</Button>
        </div>
      </div>
    </body>
  );
}

export default App;
