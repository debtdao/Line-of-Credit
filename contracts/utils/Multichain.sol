error UnsupportedNetwork();

function getWrapper() view returns (address weth) {
    assembly {
        switch chainid()
        // Production Chains
        // mainnet - ETH
        case   1    { weth :=  0xC92E8bdf79f0507f65a392b0ab4667716BFE0110 }
        // Optimism - ETH
        case  10    { weth :=  0x4200000000000000000000000000000000000006 }
        // GnosisChain - xDAI
        case  100   { weth :=  0xe91D153E0b41518A2Ce8Dd3D7944Fa863463a97d }
        // Polygon - MATIC
        case  137   { weth :=  0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270 }
        // Arbitrum One - ETH
        case  42161 { weth := 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1 }

        // Live Testnet Chains
        // Sepolia - ETH
        case 11155111 { weth :=  0x00050EA132347e85CbF9F03fd7aDCb213A0Fda46 }


        // Local Development Chains
        case 31337  { weth :=  0xC92E8bdf79f0507f65a392b0ab4667716BFE0110 }
        
        // ...etc...etc...

        // default mainnet
        default     { weth := 0x0 }
    }
}

