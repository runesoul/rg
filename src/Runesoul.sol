// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

event Deposit(
    address indexed user,
    address indexed token,
    uint256 amount,
    uint256 timestamp
);

event WithdrawRequest(
    address indexed user,
    address indexed token,
    uint256 amount,
    uint256 timestamp,
    uint256 withdrawId
);

event WithdrawConfirm(
    address indexed operator,
    address indexed user,
    address indexed token,
    uint256 amount,
    uint256 timestamp,
    uint256 withdrawId
);

event WithdrawCancel(
    address indexed operator,
    address indexed user,
    address indexed token,
    uint256 amount,
    uint256 timestamp,
    uint256 withdrawId
);

event DistributeFee(
    address indexed operator,
    address indexed distributeAddress,
    address indexed token,
    uint256 amount,
    uint256 timestamp
);

event AdminWithdraw(
    address indexed operator,
    address indexed token,
    uint256 amount,
    uint256 timestamp
);

event MerkleRootUpdated(
    address indexed operator,
    bytes32 oldRoot,
    bytes32 newRoot,
    uint256 timestamp
);

event TokenAdded(
    address indexed operator,
    address indexed token,
    uint256 minDeposit,
    uint256 timestamp
);

event TokenRemoved(
    address indexed operator,
    address indexed token,
    uint256 timestamp
);

event UserTokenAdded(
    address indexed user,
    address indexed token,
    uint256 minDeposit,
    uint256 fee,
    uint256 timestamp
);

event UserTokenRemoved(
    address indexed user,
    address indexed token,
    uint256 fee,
    uint256 timestamp
);

event UserTokenFeeUpdated(
    address indexed operator,
    uint256 oldFee,
    uint256 newFee,
    uint256 timestamp
);

event PancakeSwapInfoAdded(
    address indexed user,
    address indexed token,
    address pairedToken,
    uint256 timestamp
);

event PairedTokenMinted(
    address indexed user,
    address indexed token,
    uint256 amountIn,
    address pairedTokenAddress,
    uint256 amountOut,
    string signContext,
    bytes signature
);

event PairedTokenRewardsClaimed(
    address indexed user,
    address indexed token,
    uint256 tokenAmountOut,
    address pairedTokenAddress,
    uint256 pairedTokenAmountOut,
    string signContext,
    bytes signature
);

event TokenBought(
    address indexed user,
    address indexed token,
    uint256 amountIn,
    address outTokenAddress,
    uint256 tokenAmountOut
);

interface IPancakeRouter {
    function getAmountsOut(
        uint amountIn,
        address[] calldata path
    ) external view returns (uint[] memory amounts);
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
}

contract Runesoul is Ownable2Step, AccessControl {
    using SafeERC20 for IERC20;

    struct Withdraw {
        address user;
        address token;
        uint256 amount;
        uint256 timestamp;
        bool isConfirmed;
        bool isCanceled;
    }

    struct TokenInfo {
        bool isSupported;
        uint256 minDeposit;
        bool withdrawable;
    }

    struct PancakeSwapInfo {
        bool isSupported;
        address pairedToken;
        uint256 buyFeePercent;
        bool buySupported;
    }

    uint256 constant BPS = 10000;
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    mapping(address => TokenInfo) public supportedTokens;
    mapping(address => PancakeSwapInfo) public pancakeSwapInfos;
    IPancakeRouter public pancakeRouter;
    address[] public tokenList;

    mapping(address => uint256) public totalDeposit; // token => total deposit
    mapping(address => uint256) public totalWithdraw; // token => total withdraw
    mapping(address => uint256) public totalFee; // token => total fee

    uint256 public withdrawCount;

    address public oracle;
    uint256 public oracleNonce;

    address public feeWallet;
    uint256 public feePercent;

    address public distributeAddress;

    bytes32 public merkleRoot;

    mapping(address => mapping(address => uint256)) public playerDeposit; // user => token => amount
    mapping(address => mapping(address => uint256)) public playerWithdraw; // user => token => amount
    mapping(address => uint256) public playerWithdrawRequest; // user => withdrawId
    mapping(uint256 => Withdraw) public withdraws;

    mapping(string => bool) public usedSignContexts;

    constructor(
        address[] memory _gameTokens,
        uint256[] memory _minDeposits,
        address _oracle,
        address _feeWallet,
        uint256 _feePercent,
        address _distributeAddress,
        address _pancakeRouter
    ) Ownable(msg.sender) {
        require(
            _gameTokens.length == _minDeposits.length,
            "Arrays length mismatch"
        );

        for (uint256 i = 0; i < _gameTokens.length; i++) {
            supportedTokens[_gameTokens[i]] = TokenInfo({
                isSupported: true,
                minDeposit: _minDeposits[i],
                withdrawable: true
            });
            tokenList.push(_gameTokens[i]);
        }

        oracle = _oracle;
        feeWallet = _feeWallet;
        feePercent = _feePercent;
        distributeAddress = _distributeAddress;
        pancakeRouter = IPancakeRouter(_pancakeRouter);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        withdrawCount = 1;
    }

    function deposit(address token, uint256 amount) external {
        require(supportedTokens[token].isSupported, "Token not supported");
        require(
            amount >= supportedTokens[token].minDeposit,
            "Amount must be greater than minDeposit"
        );

        totalDeposit[token] += amount;
        playerDeposit[msg.sender][token] += amount;

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        emit Deposit(msg.sender, token, amount, block.timestamp);
    }

    function withdrawRequest(address token, uint256 amount) external {
        require(
            supportedTokens[token].isSupported &&
                supportedTokens[token].withdrawable,
            "Token not supported"
        );
        require(amount > 0, "Amount must be greater than 0");
        require(
            amount <= totalDeposit[token],
            "Amount must be less than total deposit"
        );

        if (
            !(withdraws[playerWithdrawRequest[msg.sender]].isConfirmed ||
                withdraws[playerWithdrawRequest[msg.sender]].isCanceled ||
                playerWithdrawRequest[msg.sender] == 0)
        ) {
            revert("Last withdraw request is not confirmed or canceled");
        }

        withdrawCount++;
        withdraws[withdrawCount] = Withdraw({
            user: msg.sender,
            token: token,
            amount: amount,
            timestamp: block.timestamp,
            isConfirmed: false,
            isCanceled: false
        });
        playerWithdrawRequest[msg.sender] = withdrawCount;

        emit WithdrawRequest(
            msg.sender,
            token,
            amount,
            block.timestamp,
            withdrawCount
        );
    }

    function withdrawConfirm(
        uint256 withdrawId,
        address user,
        address token,
        uint256 amount,
        bytes memory signature
    ) external onlyRole(OPERATOR_ROLE) {
        require(
            !withdraws[withdrawId].isConfirmed,
            "Withdraw request is confirmed"
        );
        require(
            !withdraws[withdrawId].isCanceled,
            "Withdraw request is canceled"
        );
        require(
            withdraws[withdrawId].user == user,
            "You are not the user of this withdraw request"
        );
        require(withdraws[withdrawId].token == token, "Token mismatch");
        require(withdraws[withdrawId].amount == amount, "Amount mismatch");

        withdraws[withdrawId].isConfirmed = true;

        emit WithdrawConfirm(
            msg.sender,
            user,
            token,
            amount,
            block.timestamp,
            withdrawId
        );

        uint8 v;
        bytes32 r;
        bytes32 s;
        assembly {
            r := mload(add(signature, 32))
            s := mload(add(signature, 64))
            v := byte(0, mload(add(signature, 96)))
        }

        oracleNonce++;
        bytes32 message = keccak256(
            abi.encodePacked(user, token, amount, withdrawId, oracleNonce)
        );
        bytes32 ethSignedMessageHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", message)
        );
        require(
            oracle == ecrecover(ethSignedMessageHash, v, r, s),
            "Invalid oracle signature"
        );

        uint256 fee = (amount * feePercent) / BPS;
        uint256 amountAfterFee = amount - fee;
        IERC20(token).safeTransfer(feeWallet, fee);
        IERC20(token).safeTransfer(user, amountAfterFee);

        playerWithdraw[user][token] += amountAfterFee;
        totalWithdraw[token] += amountAfterFee;
        totalFee[token] += fee;
    }

    function withdrawCancel(
        uint256 withdrawId,
        address user,
        bytes memory signature
    ) external onlyRole(OPERATOR_ROLE) {
        require(
            !withdraws[withdrawId].isConfirmed,
            "Withdraw request is confirmed"
        );
        require(
            !withdraws[withdrawId].isCanceled,
            "Withdraw request is canceled"
        );
        require(
            withdraws[withdrawId].user == user,
            "You are not the user of this withdraw request"
        );
        withdraws[withdrawId].isCanceled = true;

        uint8 v;
        bytes32 r;
        bytes32 s;

        assembly {
            r := mload(add(signature, 32))
            s := mload(add(signature, 64))
            v := byte(0, mload(add(signature, 96)))
        }

        oracleNonce++;

        bytes32 message = keccak256(
            abi.encodePacked(user, withdrawId, oracleNonce)
        );
        bytes32 ethSignedMessageHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", message)
        );
        require(
            oracle == ecrecover(ethSignedMessageHash, v, r, s),
            "Invalid oracle signature"
        );

        emit WithdrawCancel(
            msg.sender,
            user,
            withdraws[withdrawId].token,
            withdraws[withdrawId].amount,
            block.timestamp,
            withdrawId
        );
    }

    function distributeFee(
        address token,
        uint256 amount,
        bytes memory signature
    ) external onlyRole(OPERATOR_ROLE) {
        require(supportedTokens[token].isSupported, "Token not supported");

        uint8 v;
        bytes32 r;
        bytes32 s;
        assembly {
            r := mload(add(signature, 32))
            s := mload(add(signature, 64))
            v := byte(0, mload(add(signature, 96)))
        }

        oracleNonce++;
        bytes32 message = keccak256(
            abi.encodePacked(distributeAddress, token, amount, oracleNonce)
        );
        bytes32 ethSignedMessageHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", message)
        );
        require(
            oracle == ecrecover(ethSignedMessageHash, v, r, s),
            "Invalid oracle signature"
        );

        IERC20(token).safeTransfer(distributeAddress, amount);

        emit DistributeFee(
            msg.sender,
            distributeAddress,
            token,
            amount,
            block.timestamp
        );
    }

    function setPancakeRouter(address _pancakeRouter) external onlyOwner {
        pancakeRouter = IPancakeRouter(_pancakeRouter);
    }

    function addPancakeSwapInfos(
        address token,
        address pairedToken
    ) external onlyOwner {
        pancakeSwapInfos[token] = PancakeSwapInfo({
            isSupported: true,
            pairedToken: pairedToken,
            buyFeePercent: 0,
            buySupported: false
        });

        emit PancakeSwapInfoAdded(
            msg.sender,
            token,
            pairedToken,
            block.timestamp
        );
    }

    function addToken(address token, uint256 minDeposit) external onlyOwner {
        require(!supportedTokens[token].isSupported, "Token already supported");

        supportedTokens[token] = TokenInfo({
            isSupported: true,
            minDeposit: minDeposit,
            withdrawable: true
        });
        tokenList.push(token);

        emit TokenAdded(msg.sender, token, minDeposit, block.timestamp);
    }

    function removeToken(address token) external onlyOwner {
        require(supportedTokens[token].isSupported, "Token not supported");

        supportedTokens[token].isSupported = false;

        // Remove from tokenList
        for (uint256 i = 0; i < tokenList.length; i++) {
            if (tokenList[i] == token) {
                tokenList[i] = tokenList[tokenList.length - 1];
                tokenList.pop();
                break;
            }
        }

        emit TokenRemoved(msg.sender, token, block.timestamp);
    }

    function setWithdrawable(
        address token,
        bool _withdrawable
    ) external onlyOwner {
        require(supportedTokens[token].isSupported, "Token not supported");
        supportedTokens[token].withdrawable = _withdrawable;
    }

    function setBuyFee(
        address token,
        bool _buySupported,
        uint256 _buyFeePercent
    ) external onlyOwner {
        require(pancakeSwapInfos[token].isSupported, "Token not supported");
        pancakeSwapInfos[token].buySupported = _buySupported;
        pancakeSwapInfos[token].buyFeePercent = _buyFeePercent;
    }

    function setMinDeposit(
        address token,
        uint256 _minDeposit
    ) external onlyOwner {
        require(supportedTokens[token].isSupported, "Token not supported");
        supportedTokens[token].minDeposit = _minDeposit;
    }

    function setDistributeAddress(
        address _distributeAddress
    ) external onlyOwner {
        distributeAddress = _distributeAddress;
    }

    function setOracle(address _oracle) external onlyOwner {
        oracle = _oracle;
    }

    function setFeeWallet(address _feeWallet) external onlyOwner {
        feeWallet = _feeWallet;
    }

    function setFeePercent(uint256 _feePercent) external onlyOwner {
        require(
            _feePercent <= BPS,
            "Fee percent must be less than or equal to BPS"
        );
        feePercent = _feePercent;
    }

    function revokeOperatorRole(address account) public onlyOwner {
        revokeRole(OPERATOR_ROLE, account);
    }

    function grantOperatorRole(address account) public onlyOwner {
        grantRole(OPERATOR_ROLE, account);
    }

    function adminWithdraw(address token, uint256 amount) external onlyOwner {
        require(amount > 0, "Amount must be greater than 0");
        require(amount <= getBalance(token), "Insufficient balance");

        IERC20(token).safeTransfer(msg.sender, amount);

        emit AdminWithdraw(msg.sender, token, amount, block.timestamp);
    }

    function hasOperatorRole(address account) public view returns (bool) {
        return hasRole(OPERATOR_ROLE, account);
    }

    function getBalance(address token) public view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    function getSupportedTokens() external view returns (address[] memory) {
        return tokenList;
    }

    function buyToken(
        address token,
        uint256 amount,
        uint256 deadline
    ) external {
        require(pancakeSwapInfos[token].isSupported, "Token not supported");
        require(amount > 0, "Amount must be greater than 0");
        require(pancakeSwapInfos[token].buyFeePercent > 0, "Buy fee not set");

        uint buyFee = (pancakeSwapInfos[token].buyFeePercent * amount) / BPS;
        uint swapAmount = amount - buyFee;
        IERC20(token).safeTransferFrom(msg.sender, address(feeWallet), buyFee);
        IERC20(token).safeTransferFrom(msg.sender, address(this), swapAmount);

        address pairedToken = pancakeSwapInfos[token].pairedToken;
        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = pairedToken;

        uint estAmountOut = pancakeRouter.getAmountsOut(swapAmount, path)[1];

        IERC20(token).approve(address(pancakeRouter), swapAmount);
        uint[] memory amountOut = pancakeRouter.swapExactTokensForTokens(
            swapAmount,
            (estAmountOut * 95) / 100,
            path,
            address(this),
            deadline
        );

        emit TokenBought(msg.sender, token, amount, pairedToken, amountOut[1]);
    }

    function mintPairedToken(
        address token,
        uint256 amount,
        uint256 deadline,
        string memory signContext,
        bytes memory signature
    ) external returns (uint) {
        require(pancakeSwapInfos[token].isSupported, "Token not supported");

        require(amount > 0, "Amount must be greater than 0");
        require(amount <= getBalance(token), "Insufficient balance");
        require(deadline >= block.timestamp, "Signature expired");

        require(!usedSignContexts[signContext], "Sign context already used");

        uint8 v;
        bytes32 r;
        bytes32 s;
        assembly {
            r := mload(add(signature, 32))
            s := mload(add(signature, 64))
            v := byte(0, mload(add(signature, 96)))
        }

        bytes32 message = keccak256(
            abi.encodePacked(msg.sender, token, amount, signContext, deadline)
        );
        bytes32 ethSignedMessageHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", message)
        );
        require(
            oracle == ecrecover(ethSignedMessageHash, v, r, s),
            "Invalid oracle signature"
        );

        usedSignContexts[signContext] = true;
        address pairedToken = pancakeSwapInfos[token].pairedToken;
        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = pairedToken;

        IERC20(token).approve(address(pancakeRouter), amount);
        uint originAmount = IERC20(pairedToken).balanceOf(address(this));
        pancakeRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amount,
            0,
            path,
            address(this),
            deadline
        );
        uint amountOut = IERC20(pairedToken).balanceOf(address(this)) -
            originAmount;
        emit PairedTokenMinted(
            msg.sender,
            token,
            amount,
            pairedToken,
            amountOut,
            signContext,
            signature
        );
        return amountOut;
    }

    function claimPairedTokenRewards(
        address token,
        uint256 amount,
        uint256 deadline,
        string memory signContext,
        bytes memory signature
    ) external returns (uint[] memory amounts) {
        require(pancakeSwapInfos[token].isSupported, "Token not supported");

        require(amount > 0, "Amount must be greater than 0");
        require(amount <= getBalance(token), "Insufficient balance");
        require(deadline >= block.timestamp, "Signature expired");

        require(!usedSignContexts[signContext], "Sign context already used");

        uint8 v;
        bytes32 r;
        bytes32 s;
        assembly {
            r := mload(add(signature, 32))
            s := mload(add(signature, 64))
            v := byte(0, mload(add(signature, 96)))
        }

        bytes32 message = keccak256(
            abi.encodePacked(msg.sender, token, amount, signContext, deadline)
        );
        bytes32 ethSignedMessageHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", message)
        );
        require(
            oracle == ecrecover(ethSignedMessageHash, v, r, s),
            "Invalid oracle signature"
        );
        usedSignContexts[signContext] = true;
        address pairedToken = pancakeSwapInfos[token].pairedToken;

        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = pairedToken;

        IERC20(token).approve(address(pancakeRouter), amount);

        uint originPairedAmount = IERC20(pairedToken).balanceOf(address(this));
        pancakeRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amount,
            0,
            path,
            address(this),
            deadline
        );
        uint amountPairedOut = IERC20(pairedToken).balanceOf(address(this)) -
            originPairedAmount;

        path[0] = pairedToken;
        path[1] = token;

        uint estAmountOut = pancakeRouter.getAmountsOut(
            amountPairedOut / 2,
            path
        )[1];

        IERC20(pairedToken).approve(
            address(pancakeRouter),
            amountPairedOut / 2
        );

        uint originAmount = IERC20(token).balanceOf(address(this));
        pancakeRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountPairedOut / 2,
            (estAmountOut * 8) / 10,
            path,
            address(this),
            deadline
        );
        uint amountOut = IERC20(token).balanceOf(address(this)) - originAmount;

        emit PairedTokenRewardsClaimed(
            msg.sender,
            token,
            amountOut,
            pairedToken,
            amountPairedOut - amountPairedOut / 2,
            signContext,
            signature
        );

        uint[] memory amountsOut = new uint[](2);
        amountsOut[0] = amountOut;
        amountsOut[1] = amountPairedOut - amountPairedOut / 2;
        return amountsOut;
    }

    function getTokenInfo(
        address token
    ) external view returns (bool isSupported, uint256 minDeposit) {
        TokenInfo memory info = supportedTokens[token];
        return (info.isSupported, info.minDeposit);
    }

    function setMerkleRoot(
        bytes32 newMerkleRoot,
        bytes memory signature
    ) external onlyRole(OPERATOR_ROLE) {
        uint8 v;
        bytes32 r;
        bytes32 s;
        assembly {
            r := mload(add(signature, 32))
            s := mload(add(signature, 64))
            v := byte(0, mload(add(signature, 96)))
        }

        oracleNonce++;
        bytes32 message = keccak256(
            abi.encodePacked(newMerkleRoot, oracleNonce)
        );
        bytes32 ethSignedMessageHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", message)
        );
        require(
            oracle == ecrecover(ethSignedMessageHash, v, r, s),
            "Invalid oracle signature"
        );

        bytes32 oldRoot = merkleRoot;
        merkleRoot = newMerkleRoot;

        emit MerkleRootUpdated(
            msg.sender,
            oldRoot,
            newMerkleRoot,
            block.timestamp
        );
    }

    function verifyMerkleProof(
        bytes32[] memory proof,
        bytes32 leaf
    ) public view returns (bool) {
        bytes32 computedHash = leaf;

        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 proofElement = proof[i];

            if (computedHash <= proofElement) {
                computedHash = keccak256(
                    abi.encodePacked(computedHash, proofElement)
                );
            } else {
                computedHash = keccak256(
                    abi.encodePacked(proofElement, computedHash)
                );
            }
        }

        return computedHash == merkleRoot;
    }
}
