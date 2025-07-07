// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

event NodeCardPurchased(
    address indexed user,
    address[] tokenAddrList,
    uint256[] tokenAmountList,
    uint256 bnbAmount,
    uint256 timestamp,
    string purchaseContext,
    bytes signature
);

contract NodeCard is Ownable2Step {
    using SafeERC20 for IERC20;

    address public oracle;
    address public vault;
    uint256 public constant BNB_FEE = 0.0001 ether; // 0.0001 BNB

    constructor(address _oracle, address _vault) Ownable(msg.sender) {
        require(_oracle != address(0), "Oracle address cannot be zero");
        require(_vault != address(0), "Vault address cannot be zero");
        oracle = _oracle;
        vault = _vault;
    }

    function purchase(
        address[] memory tokenAddrList,
        uint256[] memory tokenAmountList,
        uint256 deadline,
        string memory purchaseContext,
        bytes memory signature
    ) external payable {
        require(
            tokenAddrList.length == tokenAmountList.length,
            "Arrays length mismatch"
        );
        require(tokenAddrList.length > 0, "Token list cannot be empty");
        require(block.timestamp <= deadline, "Transaction expired");
        require(msg.value >= BNB_FEE, "Insufficient BNB fee");

        uint8 v;
        bytes32 r;
        bytes32 s;
        assembly {
            r := mload(add(signature, 32))
            s := mload(add(signature, 64))
            v := byte(0, mload(add(signature, 96)))
        }

        bytes32 message = keccak256(
            abi.encodePacked(
                msg.sender,
                tokenAddrList,
                tokenAmountList,
                purchaseContext,
                deadline
            )
        );
        bytes32 ethSignedMessageHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", message)
        );
        require(
            oracle == ecrecover(ethSignedMessageHash, v, r, s),
            "Invalid oracle signature"
        );

        for (uint256 i = 0; i < tokenAddrList.length; i++) {
            require(
                tokenAddrList[i] != address(0),
                "Token address cannot be zero"
            );
            require(
                tokenAmountList[i] > 0,
                "Token amount must be greater than zero"
            );

            IERC20(tokenAddrList[i]).safeTransferFrom(
                msg.sender,
                vault,
                tokenAmountList[i]
            );
        }

        (bool success, ) = vault.call{value: BNB_FEE}("");
        require(success, "BNB transfer failed");

        if (msg.value > BNB_FEE) {
            (bool refundSuccess, ) = msg.sender.call{
                value: msg.value - BNB_FEE
            }("");
            require(refundSuccess, "BNB refund failed");
        }

        emit NodeCardPurchased(
            msg.sender,
            tokenAddrList,
            tokenAmountList,
            BNB_FEE,
            block.timestamp,
            purchaseContext,
            signature
        );
    }

    function setOracle(address _oracle) external onlyOwner {
        require(_oracle != address(0), "Oracle address cannot be zero");
        oracle = _oracle;
    }

    function setVault(address _vault) external onlyOwner {
        require(_vault != address(0), "Vault address cannot be zero");
        vault = _vault;
    }

    function emergencyWithdraw(
        address token,
        uint256 amount
    ) external onlyOwner {
        if (token == address(0)) {
            // 提取BNB
            (bool success, ) = msg.sender.call{value: amount}("");
            require(success, "BNB withdrawal failed");
        } else {
            // 提取ERC20代币
            IERC20(token).safeTransfer(msg.sender, amount);
        }
    }

    receive() external payable {}
}
