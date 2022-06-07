// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./ERC/ERC20Permit.sol";
import "./Interfaces/IAdapter.sol"; 
import "./Interfaces/IERC5095.sol";  
import "./Interfaces/IRedeemer.sol";

abstract contract ERC5095 is ERC20Permit, IERC5095 {
    /// @dev unix timestamp when the token can be redeemed
    uint256 public override immutable maturity;
    /// @dev address of the token that is redeemed
    address public override immutable underlying;
    
    //////////OPTIONAL///////////////// (Allows the calculation and distribution of yield post maturity)
    /// @dev benchmark `exchangeRate` at maturity
    uint256 public override maturityRate;
    /// @dev address and interface for an external custody contract (necessary for some project's backwards compatability)
    IRedeemer public immutable redeemer;
    /// @dev address and interface for an external cToken adapter (reads exchangeRate across a variety of protocol tokens)
    IAdapter public adapter;
    /// @dev address of a cToken
    address public cToken;

    error Maturity(uint256 timestamp);  

    constructor(address _underlying, uint256 _maturity, address _adapter, address _redeemer) {
        underlying = _underlying;
        maturity = _maturity;
        adapter = IAdapter(_adapter);
        redeemer = IRedeemer(_redeemer);
    }

    /// @notice Post maturity converts an amount of principal tokens to an amount of underlying that would be returned. Returns 0 pre-maturity.
    /// @param principalAmount The amount of principal tokens to convert
    /// @return underlyingAmount The amount of underlying tokens returned by the conversion
    function convertToUnderlying(uint256 principalAmount) external override view returns (uint256 underlyingAmount){
        if (block.timestamp < maturity) {
            return 0;
        }
        return (principalAmount * (adapter.exchangeRateCurrent(cToken) / maturityRate));
    }
    /// @notice Post maturity converts a desired amount of underlying tokens returned to principal tokens needed. Returns 0 pre-maturity.
    /// @param underlyingAmount The amount of underlying tokens to convert
    /// @return underlyingAmount The amount of principal tokens returned by the conversion
    function convertToPrincipal(uint256 underlyingAmount) external override view returns (uint256 principalAmount){
        if (block.timestamp < maturity) {
            return 0;
        }
        return(underlyingAmount * maturityRate / adapter.exchangeRateCurrent(cToken));
    }
    /// @notice Post maturity calculates the amount of principal tokens that `owner` can redeem. Returns 0 pre-maturity.
    /// @param owner The address of the owner for which redemption is calculated
    /// @return maxPrincipalAmount The maximum amount of principal tokens that `owner` can redeem.
    function maxRedeem(address owner) external override view returns (uint256 maxPrincipalAmount){
        if (block.timestamp < maturity) {
            return 0;
        }
        return(_balanceOf[owner]);
    }
    /// @notice Post maturity simulates the effects of redeemption at the current block. Returns 0 pre-maturity.
    /// @param principalAmount the amount of principal tokens redeemed in the simulation
    /// @return underlyingAmount The maximum amount of underlying returned by `principalAmount` of PT redemption
    function previewRedeem(uint256 principalAmount) external override view returns (uint256 underlyingAmount){
        if (block.timestamp < maturity) {
            return 0;
        }
        return(principalAmount * (adapter.exchangeRateCurrent(cToken) / maturityRate));
    }
    /// @notice Post maturity calculates the amount of underlying tokens that `owner` can withdraw. Returns 0 pre-maturity.
    /// @param address owner The address of the owner for which withdrawal is calculated
    /// @return maxUnderlyingAmount The maximum amount of underlying tokens that `owner` can withdraw.
    function maxWithdraw(address owner) external override view returns (uint256 maxUnderlyingAmount){
        if (block.timestamp < maturity) {
            return 0;
        }
        return(_balanceOf[owner] * (adapter.exchangeRateCurrent(cToken) / maturityRate));
    }
    /// @notice Post maturity simulates the effects of withdrawal at the current block. Returns 0 pre-maturity.
    /// @param underlyingAmount the amount of underlying tokens withdrawn in the simulation
    /// @return principalAmount The amount of principal tokens required for the withdrawal of `underlyingAmount`
    function previewWithdraw(uint256 underlyingAmount) external override view returns (uint256 principalAmount){
        if (block.timestamp < maturity) {
            return 0;
        }
        return(underlyingAmount * maturityRate / adapter.exchangeRateCurrent(cToken));
    }
    /// @notice At or after maturity, Burns principalAmount from owner and sends exactly underlyingAmount of underlying tokens to receiver.
    /// @param underlyingAmount The amount of underlying tokens withdrawn
    /// @param owner The owner of the principal tokens being redeemed
    /// @param receiver The receiver of the underlying tokens being withdrawn
    /// @return principalAmount The amount of principal tokens burnt by the withdrawal
    function withdraw(uint256 underlyingAmount, address owner, address receiver) external override returns (uint256 principalAmount){
        if (maturityRate == 0) {
            if (block.timestamp < maturity) {
                revert Maturity(maturity);
            }
            maturityRate = adapter.exchangeRateCurrent(cToken);
            return redeemer.adminRedeem(underlying, maturity, owner, receiver, underlyingAmount);
        }
        return redeemer.adminRedeem(underlying, maturity, owner, receiver, (underlyingAmount * maturityRate / adapter.exchangeRateCurrent(cToken)));
    }
    /// @notice At or after maturity, burns exactly principalAmount of Principal Tokens from from and sends underlyingAmount of underlying tokens to to.
    /// @param principalAmount The amount of principal tokens being redeemed
    /// @param owner The owner of the principal tokens being redeemed
    /// @param receiver The receiver of the underlying tokens being withdrawn
    /// @return principalAmount The amount of underlying tokens distributed by the redemption
    function redeem(uint256 principalAmount, address owner, address receiver) external override returns (uint256 underlyingAmount){
        if (maturityRate == 0) {
            if (block.timestamp < maturity) {
                revert Maturity(maturity);
            }
            maturityRate = adapter.exchangeRateCurrent(cToken);
        }
        // some 5095 tokens may have custody of underlying and can just transfer underlying out, while others rely on external custody
        return redeemer.authRedeem(underlying, maturity, owner, receiver, principalAmount);
    }
}
