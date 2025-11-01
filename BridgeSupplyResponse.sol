// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract BridgeSupplyResponse {
    
    event BridgeSupplyAlert(
        address indexed token,
        uint256 oldSupply,
        uint256 newSupply
    );

    function respondWithSupplyAlert(
        address token,
        uint256 oldSupply,
        uint256 newSupply
    ) external {
        emit BridgeSupplyAlert(token, oldSupply, newSupply);
    }
}
