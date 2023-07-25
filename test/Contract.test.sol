// SPDX-License-Identifier: APACHE
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../src/Contract.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address account, uint256 amount) public {
        _mint(account, amount);
    }
}

contract TokenizedVaultTest is Test {
    TokenizedVault _vault;
    ExternalAsset _externalAsset;
    IERC20 _asset;
    address _mockExternalContract;

    function setUp() public {
        // Set up the _asset and mock external contract.
        // The _asset and _mockExternalContract would ideally be mock tokens that we have control over.
        // For this example, we'll just use a new instance of the MockERC20 contract and address(2).
        _asset = new MockERC20("Mock Token", "MCK");
        _mockExternalContract = address(2);

        // Set up the _vault with the _asset, name, and symbol.
        _vault = new TokenizedVault(_asset, "Vault", "VAULT", 0, 1000000000000);

        // Set up the external _asset.
        // This is created in the constructor of the _vault.
        _externalAsset = _vault.getExternalAsset();

    }

    function testMintExternalAsset() public {
        uint256 amount = 100;
        _vault.mintExternalAsset(address(this), amount);

        assertEq(_vault.totalExternalAssets(), amount);
    }

    function testBurnExternalAsset() public {
        uint256 amount = 100;
        _vault.mintExternalAsset(address(this), amount);
        _vault.burnExternalAsset(address(this), amount);

        assertEq(_vault.totalExternalAssets(), 0);
    }

    function testInvestExternally() public {
        uint256 amount = 100;

        // Mint _asset tokens for the _vault.
        MockERC20(address(_asset)).mint(address(_vault), amount);

        // Allow the _vault to spend our tokens.
        _asset.approve(address(_vault), amount);

        _vault.investExternally(address(this), _mockExternalContract, amount);

        // Check that the _vault has spent our _asset tokens.
        assertEq(_asset.balanceOf(_mockExternalContract), amount);

        // Check that we have been minted external _asset tokens.
        assertEq(_vault.totalExternalAssets(), amount);
    }

    function testRedeemExternalInvestment() public {
        uint256 amount = 100;

        // Invest some _asset tokens externally.
        MockERC20(address(_asset)).mint(address(_vault), amount);
        _asset.approve(address(_vault), amount);
        _vault.investExternally(address(this), _mockExternalContract, amount);

        // Now redeem our external investment.
        // For this, the mock external contract needs to have enough tokens and allowance to send them to us.
        MockERC20(address(_asset)).mint(address(_vault), amount);
        _asset.approve(address(_vault), amount);

        _vault.redeemExternalInvestment(
            address(this),
            _mockExternalContract,
            amount
        );

        // Check that we received our _asset tokens back.
        assertEq(_asset.balanceOf(address(this)), amount);

        // Check that our external _asset tokens have been burned.
        assertEq(_vault.totalExternalAssets(), 0);
    }

    function testFailInvestExternallyWithoutAllowance() public {
        uint256 amount = 100;
        MockERC20(address(_asset)).mint(address(_vault), amount);

        // Here we're not approving the _vault to spend our tokens,
        // so this should fail.
        _vault.investExternally(address(this), _mockExternalContract, amount);
    }
}
