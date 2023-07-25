// SPDX-License-Identifier: APACHE

pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title ExternalAsset
 * @dev This is a simple ERC20 contract that will be used to represent assets that
 * have been invested externally.
 */
contract ExternalAsset is ERC20, ERC20Burnable, Ownable {
    uint8 private _decimals;

    constructor(uint8 decimals_) ERC20("External Asset", "EXT") {
        _decimals = decimals_;
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    function burnFrom(
        address account,
        uint256 amount
    ) public override onlyOwner {
        _burn(account, amount);
    }
}

/**
 * @title TokenizedVault
 * @dev This contract is a concrete implementation of ERC4626.
 */
contract TokenizedVault is ERC4626, Ownable, Pausable, ReentrancyGuard {
    string private _name;
    string private _symbol;
    ExternalAsset private _externalAsset;
    uint8 private _decimals;
    uint256 public minDepositSize;
    uint256 public maxDepositSize;

    /**
     * @dev Sets the values for {name} and {symbol}, initializes the underlying
     * asset with the value of {asset_}
     */
    constructor(
        IERC20 asset_,
        string memory name_,
        string memory symbol_,
        uint256 minDepositSize_,
        uint256 maxDepositSize_
    ) ERC4626(asset_) ERC20(name_, symbol_) Ownable() {
        _name = name_;
        _symbol = symbol_;
        _decimals = ERC20(address(asset_)).decimals();
        _externalAsset = new ExternalAsset(_decimals);
        _externalAsset.transferOwnership(address(this));
        minDepositSize = minDepositSize_;
        maxDepositSize = maxDepositSize_;
    }

    /**
     * @dev Returns the name of the token.
     */
    function name()
        public
        view
        virtual
        override(ERC20, IERC20Metadata)
        returns (string memory)
    {
        return _name;
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol()
        public
        view
        virtual
        override(ERC20, IERC20Metadata)
        returns (string memory)
    {
        return _symbol;
    }

    /**
     * @dev Returns the amount of decimals used to get its user representation.
     * For example, if `decimals` equals `2`, a balance of `505` tokens should
     * be displayed to a user as `5,05` (`505 / 10 ** 2`).
     *
     * Tokens usually opt for a value of 18, imitating the relationship between
     * Ether and Wei. This is the value {ERC20} uses, unless this function is
     * overridden;
     *
     * NOTE: This information is only used for _display_ purposes: it in
     * no way affects any of the arithmetic of the contract, including
     * {IERC20-balanceOf} and {IERC20-transfer}.
     */
    function decimals() public view virtual override(ERC4626) returns (uint8) {
        return _decimals;
    }

    /**
     * @dev Mints tokens for the investor and transfers the underlying asset to this contract.
     */
    function deposit(uint256 amount) public {
        // Check that the amount meets the minimum and maximum requirements.
        require(amount > 0, "Deposit amount must be greater than zero");
        require(
            amount >= minDepositSize,
            "Deposit amount is less than the minimum"
        );
        require(amount <= maxDepositSize, "Deposit amount exceeds the maximum");

        // Transfer the tokens from the investor to this contract
        require(
            IERC20(asset()).transferFrom(msg.sender, address(this), amount),
            "Transfer failed"
        );

        // Mint an equivalent amount of this contract's tokens for the investor
        _mint(msg.sender, amount);
    }

    /**
     * @dev Returns the total balance of assets and external assets of an account.
     */
    function totalAllAssets(address account) public view returns (uint256) {
        uint256 assetBalance = balanceOf(account);
        uint256 externalAssetBalance = _externalAsset.balanceOf(account);
        return assetBalance + externalAssetBalance;
    }

    /**
     * @dev Returns the total amount of the external assets that is “managed” by Vault.
     */
    function totalExternalAssets() public view virtual returns (uint256) {
        return _externalAsset.balanceOf(address(this));
    }

    /**
     * @dev Returns the _externalAsset object, if it exists.
     */
    function getExternalAsset() public view returns (ExternalAsset) {
        require(
            address(_externalAsset) != address(0),
            "ExternalAsset has not been set"
        );
        return _externalAsset;
    }

    /**
     * @dev Allows the owner of the contract to invest assets externally on behalf of an investor.
     */
    function investExternally(
        address from,
        address externalContract,
        uint256 amount
    ) public onlyOwner {
        IERC20 token = IERC20(asset());
        require(
            token.allowance(from, address(this)) >= amount,
            "Not enough allowance"
        );

        // Transfer the tokens from the specified account to the external contract
        require(
            token.transferFrom(from, externalContract, amount),
            "Transfer failed"
        );

        // Mint the external asset tokens
        _externalAsset.mint(from, amount);
    }

    /**
     * @dev Allows the owner of the contract to redeem an external investment on behalf of an investor.
     * The amount to redeem can be more or less than the amount invested.
     * --- Screnario 1: The investor makes a profit.
     * If the amount to redeem is more than the amount invested then the investor has earned a profit.
     * In this case the investor will receive the amount invested plus the profit and all external asset tokens will be burned.
     * --- Screnario 2: The investor makes a loss.
     * If the amount to redeem is less than the amount invested then the investor has lost money.
     * If this case the investor will receive the amount to be redeemed and only the amount to be redeemed of external asset tokens will be burned.
     * Any spare external asset tokens will remain in the vault for this investor.
     */
    function redeemExternalInvestment(
        address investor,
        address externalContract,
        uint256 amount
    ) public onlyOwner {
        require(amount > 0, "Amount must be greater than zero");

        // Get the balance of external asset tokens for the investor
        uint256 externalBalance = _externalAsset.balanceOf(investor);

        // Determine the amount of external asset tokens to burn.
        // If the investor has less external asset tokens than the amount to burn,
        // then burn the entire balance.
        uint256 amountToBurn = (externalBalance < amount)
            ? externalBalance
            : amount;

        IERC20 token = IERC20(asset());

        // Check allowance
        uint256 allowance = token.allowance(externalContract, address(this));
        require(allowance >= amountToBurn, "Transfer amount exceeds allowance");

        // Transfer the underlying asset tokens from the external contract to the investor
        require(
            token.transferFrom(externalContract, investor, amountToBurn),
            "Transfer failed"
        );

        // Burn the external asset tokens
        // We have checked that this won't fail due to insufficient balance
        // in the previous step.
        // In addition, the external asset contract is owned by this contract,
        // so only this contract can burn tokens.
        _externalAsset.burnFrom(investor, amountToBurn);
    }

    /**
     * @dev Allows the owner of the contract to burn external asset tokens on behalf of an investor.
     */
    function burnExternalAsset(
        address investor,
        uint256 amount
    ) public onlyOwner {
        require(amount > 0, "Burn amount must be greater than zero");

        // Check that the investor has enough tokens to burn
        uint256 balance = _externalAsset.balanceOf(investor);
        require(balance >= amount, "Burn amount exceeds investor balance");

        // Burn the external asset tokens
        _externalAsset.burnFrom(investor, amount);
    }

    /**
     * @dev Allows the owner of the contract to mint external asset tokens on behalf of an investor.
     */
    function mintExternalAsset(
        address investor,
        uint256 amount
    ) public onlyOwner {
        require(amount > 0, "Mint amount must be greater than zero");

        // Mint the external asset tokens
        _externalAsset.mint(investor, amount);
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }
}
