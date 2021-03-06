// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./ERC/ERC20.sol";
import "./Utils/Compounding.sol";
import "./Interfaces/IERC5095.sol";  
import "./Interfaces/IRedeemer.sol";

// Utilizing an external custody contract to allow for backwards compatability with some projects.
// Assumes interest generated post maturity using an internal Compounding library.
abstract contract ERC5095 is ERC20, IERC5095 {
    /// @dev unix timestamp when the ERC5095 token can be redeemed
    uint256 public override immutable maturity;
    /// @dev address of the ERC20 token that is returned on ERC5095 redemption
    address public override immutable underlying;
    /// @dev uint8 associated with a given protocol in Swivel
    uint8 public immutable protocol;
    
    /////////////OPTIONAL///////////////// (Allows the calculation and distribution of yield post maturity)
    /// @dev address of a cToken
    address public immutable cToken;
    /// @dev address and interface for an external custody contract (necessary for some project's backwards compatability)
    IRedeemer public immutable redeemer;
    /// @dev benchmark `exchangeRate` at maturity
    uint256 public override maturityRate;

    event Matured(uint256 timestamp, uint256 exchangeRate);

    error Maturity(uint256 timestamp);  

    error Approvals(uint256 approved, uint256 amount);

    constructor(address _underlying, uint256 _maturity, address _cToken, uint8 _protocol, address _redeemer) {
        underlying = _underlying;
        maturity = _maturity;
        protocol = _protocol;
        redeemer = IRedeemer(_redeemer);
        cToken = _cToken;
    }

    /// @notice Post maturity converts an amount of principal tokens to an amount of underlying that would be returned. Returns 0 pre-maturity.
    /// @param principalAmount The amount of principal tokens to convert
    /// @return underlyingAmount The amount of underlying tokens returned by the conversion
    function convertToUnderlying(uint256 principalAmount) external override view returns (uint256 underlyingAmount){
        if (block.timestamp < maturity) {
            return 0;
        }
        return (principalAmount * Compounding.exchangeRate(protocol, cToken) / maturityRate);
    }
    /// @notice Post maturity converts a desired amount of underlying tokens returned to principal tokens needed. Returns 0 pre-maturity.
    /// @param underlyingAmount The amount of underlying tokens to convert
    /// @return principalAmount The amount of principal tokens returned by the conversion
    function convertToPrincipal(uint256 underlyingAmount) external override view returns (uint256 principalAmount){
        if (block.timestamp < maturity) {
            return 0;
        }
        return (underlyingAmount * maturityRate / Compounding.exchangeRate(protocol, cToken));
    }
    /// @notice Post maturity calculates the amount of principal tokens that `owner` can redeem. Returns 0 pre-maturity.
    /// @param owner The address of the owner for which redemption is calculated
    /// @return maxPrincipalAmount The maximum amount of principal tokens that `owner` can redeem.
    function maxRedeem(address owner) external override view returns (uint256 maxPrincipalAmount){
        if (block.timestamp < maturity) {
            return 0;
        }
        return (balanceOf[owner]);
    }
    /// @notice Post maturity simulates the effects of redeemption at the current block. Returns 0 pre-maturity.
    /// @param principalAmount the amount of principal tokens redeemed in the simulation
    /// @return underlyingAmount The maximum amount of underlying returned by `principalAmount` of PT redemption
    function previewRedeem(uint256 principalAmount) external override view returns (uint256 underlyingAmount){
        if (block.timestamp < maturity) {
            return 0;
        }
        return (principalAmount * Compounding.exchangeRate(protocol, cToken) / maturityRate);
    }
    /// @notice Post maturity calculates the amount of underlying tokens that `owner` can withdraw. Returns 0 pre-maturity.
    /// @param  owner The address of the owner for which withdrawal is calculated
    /// @return maxUnderlyingAmount The maximum amount of underlying tokens that `owner` can withdraw.
    function maxWithdraw(address owner) external override view returns (uint256 maxUnderlyingAmount){
        if (block.timestamp < maturity) {
            return 0;
        }
        return (balanceOf[owner] * Compounding.exchangeRate(protocol, cToken) / maturityRate);
    }
    /// @notice Post maturity simulates the effects of withdrawal at the current block. Returns 0 pre-maturity.
    /// @param underlyingAmount the amount of underlying tokens withdrawn in the simulation
    /// @return principalAmount The amount of principal tokens required for the withdrawal of `underlyingAmount`
    function previewWithdraw(uint256 underlyingAmount) external override view returns (uint256 principalAmount){
        if (block.timestamp < maturity) {
            return 0;
        }
        return (underlyingAmount * maturityRate / Compounding.exchangeRate(protocol, cToken));
    }
    /// @notice At or after maturity, Burns principalAmount from `owner` and sends exactly `underlyingAmount` of underlying tokens to `receiver`.
    /// @param underlyingAmount The amount of underlying tokens withdrawn
    /// @param receiver The receiver of the underlying tokens being withdrawn
    /// @return principalAmount The amount of principal tokens burnt by the withdrawal
    function withdraw(uint256 underlyingAmount, address receiver, address holder) external override returns (uint256 principalAmount){
        uint256 previewAmount = this.previewWithdraw(underlyingAmount);    
        // If not matured yet
        if (maturityRate == 0) {
            // If maturity is not yet reached
            if (block.timestamp < maturity) {
                revert Maturity(maturity);
            }
            // If not reverting, "mature" the market by setting the maturityRate and emitting event
            maturityRate = Compounding.exchangeRate(protocol, cToken);
            emit Matured(block.timestamp, maturityRate);
        // Transfer logic
        // If holder is msg.sender, skip approval check
            if (holder == msg.sender) {
                return redeemer.authRedeem(underlying, maturity, msg.sender, receiver, previewAmount);
            }
            else {
                uint256 allowed = allowance[holder][msg.sender];
                if (allowed >= previewAmount) {
                    revert Approvals(allowed, previewAmount);
                }
                allowance[holder][msg.sender] -= previewAmount;
                return redeemer.authRedeem(underlying, maturity, holder, receiver, previewAmount);     
            }
        }
        // If already matured
        // If holder is msg.sender, skip approval check
        if (holder == msg.sender) {
            return redeemer.authRedeem(underlying, maturity, msg.sender, receiver, previewAmount);
        }
        else {
            uint256 allowed = allowance[holder][msg.sender];
            if (allowed >= previewAmount) {
                revert Approvals(allowed, previewAmount);
            }
            allowance[holder][msg.sender] -= previewAmount;
            return redeemer.authRedeem(underlying, maturity, holder, receiver, previewAmount);     
        }
    }
    /// @notice At or after maturity, burns exactly `principalAmount` of Principal Tokens from `owner` and sends underlyingAmount of underlying tokens to `receiver`.
    /// @param principalAmount The amount of principal tokens being redeemed
    /// @param receiver The receiver of the underlying tokens being withdrawn
    /// @return underlyingAmount The amount of underlying tokens distributed by the redemption
    function redeem(uint256 principalAmount, address receiver, address holder) external override returns (uint256 underlyingAmount){
        
        if (maturityRate == 0) {
            if (block.timestamp < maturity) {
                revert Maturity(maturity);
            }
            maturityRate = Compounding.exchangeRate(protocol, cToken);
            emit Matured(block.timestamp, maturityRate);
        }
        // some 5095 tokens may have custody of underlying and can can just burn PTs and transfer underlying out, while others rely on external custody
        if (holder == msg.sender) {
            return redeemer.authRedeem(underlying, maturity, msg.sender, receiver, principalAmount);
        }
        else {
            uint256 allowed = allowance[holder][msg.sender];
            if (allowed >= principalAmount) {
                revert Approvals(allowed, principalAmount);
            }
            allowance[holder][msg.sender] -= principalAmount;
            return redeemer.authRedeem(underlying, maturity, holder, receiver, principalAmount);     
        }
    }
}