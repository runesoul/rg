// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IPancakeFactory {
    function createPair(
        address tokenA,
        address tokenB
    ) external returns (address pair);
}

interface IPancakeRouter {
    function factory() external pure returns (address);
}

interface IPancakePair {
    function sync() external;
}

contract RUC {
    string public name = "RUC";
    string public symbol = "RUC";
    uint8 public decimals = 18;
    uint256 public totalSupply = 1000000000000 * 10 ** uint256(decimals);

    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status;

    address public owner;
    address public taxWallet;
    address public pancakePair;
    IPancakeRouter public router;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    mapping(address => bool) public isTaxExempt;
    mapping(address => bool) public isWhitelist;
    bool public buyEnabled = true;
    uint256 public taxPercent = 15;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
    event OwnershipTransferred(
        address indexed oldOwner,
        address indexed newOwner
    );
    event PoolDeflated(uint256 deflationAmount, uint256 deflatedAt);
    event FeeReceived(
        address indexed from,
        address indexed feeWallet,
        uint256 amount
    );

    modifier onlyOwner() {
        require(msg.sender == owner, "Not admin");
        _;
    }

    modifier nonReentrant() {
        // On the first call to nonReentrant, _notEntered will be true
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");

        // Any calls to nonReentrant after this point will fail
        _status = _ENTERED;

        _;

        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = _NOT_ENTERED;
    }

    constructor(address _router, address rgToken) {
        owner = msg.sender;
        taxWallet = msg.sender;
        router = IPancakeRouter(_router);

        _status = _NOT_ENTERED;

        balanceOf[msg.sender] = totalSupply;
        emit Transfer(address(0), msg.sender, totalSupply);

        address _pair = IPancakeFactory(router.factory()).createPair(
            rgToken,
            address(this)
        );
        pancakePair = _pair;
    }

    function transfer(
        address to,
        uint256 value
    ) public nonReentrant returns (bool) {
        return _transfer(msg.sender, to, value);
    }

    function approve(
        address spender,
        uint256 value
    ) public nonReentrant returns (bool) {
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) public nonReentrant returns (bool) {
        require(allowance[from][msg.sender] >= value, "Allowance exceeded");
        allowance[from][msg.sender] -= value;
        return _transfer(from, to, value);
    }

    function _transfer(
        address from,
        address to,
        uint256 value
    ) internal returns (bool) {
        require(balanceOf[from] >= value, "Insufficient balance");

        if (from == pancakePair && !buyEnabled) {
            require(isWhitelist[to], "Buy not enabled");
        }

        uint256 tax = 0;
        if (!isTaxExempt[from] && !isTaxExempt[to]) {
            if (from == pancakePair || to == pancakePair) {
                tax = (value * taxPercent) / 100;
            }
        }

        balanceOf[from] -= value;
        balanceOf[to] += (value - tax);

        if (tax > 0) {
            balanceOf[taxWallet] += tax;
            emit Transfer(from, taxWallet, tax);
            emit FeeReceived(from, taxWallet, tax);
        }

        emit Transfer(from, to, value - tax);
        return true;
    }

    function setTaxWallet(address _wallet) external onlyOwner {
        taxWallet = _wallet;
    }

    function setTaxExempt(address _addr, bool _status) external onlyOwner {
        isTaxExempt[_addr] = _status;
    }

    function setBuyEnabled(bool _enabled) external onlyOwner {
        buyEnabled = _enabled;
    }

    function setBuyWhitelist(address _addr, bool _status) external onlyOwner {
        isWhitelist[_addr] = _status;
    }

    function setTaxPercent(uint256 _percent) external onlyOwner {
        require(_percent <= 20, "Max 20%");
        taxPercent = _percent;
    }

    function setPancakePair(address _pair) external onlyOwner {
        pancakePair = _pair;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    function poolDeflation() public onlyOwner returns (bool) {
        uint256 accountBalance = balanceOf[pancakePair];
        require(accountBalance > 0, "No tokens to burn");

        uint256 burnAmount = (accountBalance * 20) / 1000;
        require(burnAmount > 0, "Burn amount too small");

        _burn(pancakePair, burnAmount);
        IPancakePair(pancakePair).sync();
        emit PoolDeflated(burnAmount, block.timestamp);
        return true;
    }

    function _burn(address account, uint256 amount) internal {
        require(account != address(0), "Burn from zero address");
        require(balanceOf[account] >= amount, "Burn amount exceeds balance");

        balanceOf[account] -= amount;
        totalSupply -= amount;

        emit Transfer(account, address(0), amount);
    }
}
