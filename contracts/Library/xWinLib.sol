// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library xWinLib {
   
    
    struct transferData {      
      uint256 totalTrfAmt;
      uint256 totalUnderlying;
    }
    
    struct UnderWeightData {
      uint256 activeWeight;
      address token;
    }
    
    struct DeletedNames {
      address token;
      uint256 targetWeight;
    }

}