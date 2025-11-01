// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ITrap} from "drosera-contracts/interfaces/ITrap.sol";

/**
 * @dev Minimal ERC20 interface to get totalSupply.
 */
interface IERC20Minimal {
    function totalSupply() external view returns (uint256);
}

/**
 * @title BridgeSupplyTrap
 * @author Kingflirckz
 * @notice This trap detects an anomalous, rapid increase in the total supply
 * of a bridged token, which could signal a bridge exploit.
 * (Corrected to be 'pure' compatible).
 */
contract BridgeSupplyTrap is ITrap {
    address public owner;
    IERC20Minimal public targetBridgedToken;

    /**
     * @notice The maximum amount the total supply can increase over the
     * operator's 'block_sample_size' window.
     */
    uint256 public maxSupplyIncrease;

    // --- Struct for data packet ---
    /**
     * @notice This is the data packet that collect() will return.
     * It includes the token address, its current supply, and the threshold
     * so that shouldRespond() can be pure.
     */
    struct SupplyData {
        address tokenAddress;
        uint256 totalSupply;
        uint256 maxIncreaseThreshold;
    }

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "BridgeSupplyTrap: only owner");
        _;
    }

    /**
     * @notice Set the bridged token contract to monitor.
     */
    function setTargetToken(address _token) external onlyOwner {
        targetBridgedToken = IERC20Minimal(_token);
    }

    /**
     * @notice Set the max allowed supply increase over the sample period.
     */
    function setMaxSupplyIncrease(uint256 _maxIncrease) external onlyOwner {
        maxSupplyIncrease = _maxIncrease;
    }

    // ------------------------------------------------------------------------
    // ITrap implementation
    // ------------------------------------------------------------------------

    /**
     * @notice Collects the current total supply and the config threshold.
     * Called by the Drosera operator at each block in the sample.
     * @return (bytes memory) abi.encoded (SupplyData)
     */
    function collect() external view override returns (bytes memory) {
        uint256 currentTotalSupply = 0;
        address tokenAddr = address(targetBridgedToken);

        if (tokenAddr != address(0)) {
            currentTotalSupply = targetBridgedToken.totalSupply();
        }

        // Encode the current state AND the configuration
        // This allows shouldRespond to be pure
        SupplyData memory dataPacket = SupplyData({
            tokenAddress: tokenAddr,
            totalSupply: currentTotalSupply,
            maxIncreaseThreshold: maxSupplyIncrease
        });

        return abi.encode(dataPacket);
    }

    /**
     * @notice Pure check on the array of collected data.
     * @param data An array of (bytes memory) from multiple 'collect()' calls.
     * data[0] is the LATEST data.
     * data[data.length-1] is the OLDEST data.
     * @return shouldRespond True if an alert should be triggered.
     * @return responseData The encoded (address token, uint256 oldSupply, uint256 newSupply)
     */
    function shouldRespond(
        bytes[] calldata data
    ) external pure override returns (bool, bytes memory) {
        // Need at least two data points to compare
        if (data.length < 2) {
            return (false, "");
        }

        // data[0] is the latest data point
        SupplyData memory latestData = abi.decode(data[0], (SupplyData));

        // data[data.length - 1] is the oldest data point in the sample
        SupplyData memory oldestData = abi.decode(
            data[data.length - 1],
            (SupplyData)
        );

        // We use the threshold from the *latest* data packet,
        // as this reflects the most current setting.
        uint256 currentMaxIncrease = latestData.maxIncreaseThreshold;
        uint256 newSupply = latestData.totalSupply;
        uint256 oldSupply = oldestData.totalSupply;
        address tokenAddress = latestData.tokenAddress;

        // Check for invalid state (e.g., trap not fully configured)
        if (currentMaxIncrease == 0 || tokenAddress == address(0)) {
            return (false, "");
        }

        // Check for the anomaly
        if (newSupply > oldSupply) {
            uint256 supplyDelta = newSupply - oldSupply;

            if (supplyDelta > currentMaxIncrease) {
                // Anomaly detected!
                return (
                    true,
                    abi.encode(tokenAddress, oldSupply, newSupply)
                );
            }
        }

        // No anomaly
        return (false, "");
    }
}
