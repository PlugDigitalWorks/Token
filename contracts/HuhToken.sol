// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;


//      ██╗  ██╗██╗   ██╗██╗  ██╗    ████████╗ ██████╗ ██╗  ██╗███████╗███╗   ██╗
//      ██║  ██║██║   ██║██║  ██║    ╚══██╔══╝██╔═══██╗██║ ██╔╝██╔════╝████╗  ██║
//      ███████║██║   ██║███████║       ██║   ██║   ██║█████╔╝ █████╗  ██╔██╗ ██║
//      ██╔══██║██║   ██║██╔══██║       ██║   ██║   ██║██╔═██╗ ██╔══╝  ██║╚██╗██║
//      ██║  ██║╚██████╔╝██║  ██║       ██║   ╚██████╔╝██║  ██╗███████╗██║ ╚████║
//      ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝       ╚═╝    ╚═════╝ ╚═╝  ╚═╝╚══════╝╚═╝  ╚═══╝


import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./interfaces/IBEP20.sol";
import "./interfaces/IDividendDistributor.sol";
import { DividendDistributor, IDividendDistributor } from "./dividends/DividendDistributor.sol";
import { IUniswapV2Pair, IUniswapV2Router02, IUniswapV2Factory } from "./interfaces/IUniswap.sol";


contract HuhToken is Context, IBEP20, Ownable {
    using SafeMath for uint256;

    string constant _NAME = "HuhToken";
    string constant _SYMBOL = "HUH";
    uint8 constant _DECIMALS = 9;

    uint256 private constant _MAX = ~uint256(0);
    uint256 private _tTotal = 1 * 10 ** 15 * ( 10** _DECIMALS); // 1 Quadrilion HUH
    uint256 private _rTotal = (_MAX - (_MAX % _tTotal));
    uint256 private _tFeeTotal;


    //  +---------------------------+------+-----+------+------------+--------------+---------+
    //  |                           | BNB% | LP% | HUH% | Marketing% | Layer 2 BNB% | Total % |
    //  +---------------------------+------+-----+------+------------+--------------+---------+
    //  | Normal Buy                | 5    | 1   | 8    | 1          |              | 15      |
    //  | Whitelisted Buy (layer 1) | 10   | 1   | 3    | 1          |              | 15      |
    //  | Whitelisted Buy (layer 2) | 10   | 1   | 1    | 1          | 2            | 15      |
    //  | Normal Sell               | 5    | 1   | 8    | 1          |              | 15      |
    //  | Whitelisted Sell          | 5    | 1   | 3    | 1          |              | 10      |
    //  +---------------------------+------+-----+------+------------+--------------+---------+

    uint256 public liquidityFeeOnBuy = 1;
    uint256 public BNBreflectionFeeOnBuy = 5;
    uint256 public marketingFeeOnBuy = 1;
    uint256 public HuHdistributionFeeOnBuy = 8;

    uint256 public liquidityFeeOnBuyWhiteListed_A = 1;
    uint256 public BNBrewardFor1stPerson_A = 10;
    uint256 public marketingFeeOnBuyWhiteListed_A = 1;
    uint256 public HuHdistributionFeeOnBuyWhiteListed_A = 3;

    uint256 public liquidityFeeOnBuyWhiteListed_B = 1;
    uint256 public BNBrewardFor1stPerson_B = 10;
    uint256 public BNBrewardFor2ndPerson_B = 2;
    uint256 public marketingFeeOnBuyWhiteListed_B = 1;
    uint256 public HuHdistributionFeeOnBuyWhiteListed_B = 1;

    uint256 public liquidityFeeOnSell = 1;
    uint256 public BNBreflectionFeeOnSell = 5;
    uint256 public marketingFeeOnSell = 1;
    uint256 public HuHdistributionFeeOnSell = 8;

    uint256 public liquidityFeeOnSellWhiteListed = 1;
    uint256 public BNBreflectionFeeOnSellWhiteListed = 5;
    uint256 public marketingFeeOnSellWhiteListed = 1;
    uint256 public HuHdistributionFeeOnSellWhiteListed = 3;

    uint256 public launchedAt;
    uint256 public distributorGas = 500000;
    uint256 public minTokenAmountForGetReward = 10000 * (10 ** _DECIMALS);

    address public refCodeRegistrator;  // Address who allowed to register code for users (will be used later)
    address public marketingFeeReceiver;
    address private constant _DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    mapping(address => uint256) private _rOwned;
    mapping(address => uint256) private _tOwned;
    mapping(address => mapping(address => uint256)) private _allowances;

    mapping(address => bool) private _isExcludedFromFee;
    mapping(address => bool) private _isExcludedFromDividend;
    mapping(address => bool) private _isExcluded;
    address[] private _excluded;

    mapping(address => bytes) public referCodeForUser;
    mapping(bytes => address) public referUserForCode;
    mapping(address => address) public referParent;
    mapping(address => bool) public isWhitelisted;
    mapping(address => bool) public isFirstBuy;

    IUniswapV2Router02 public pcsV2Router;
    address public pcsV2Pair;

    IDividendDistributor public distributor;

    address public reward1stPerson;
    address public reward2ndPerson;
    mapping(address => uint256) public rewardAmount;

    bool public swapEnabled = true;
    uint256 public swapThreshold = 200000 * (10 ** _DECIMALS); // Swap every 200k tokens
    uint256 private _liquidityAccumulated;

    bool private _inSwap;
    modifier swapping() {
        _inSwap = true;
        _;
        _inSwap = false;
    }

    event UserWhitelisted(address account, address referee);
    event CodeRegisterred(address account, bytes code);
    event SwapAndLiquify(
        uint256 ethReceived,
        uint256 tokensIntoLiqudity
    );


    //  -----------------------------
    //  CONSTRUCTOR
    //  -----------------------------


    constructor() {
        IUniswapV2Router02 _pancakeswapV2Router =
            IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E);

        // Create a uniswap pair for this new token
        pcsV2Pair = IUniswapV2Factory(_pancakeswapV2Router.factory()).createPair(
            address(this),
            _pancakeswapV2Router.WETH()
        );
        pcsV2Router = _pancakeswapV2Router;
        _allowances[address(this)][address(pcsV2Router)] = _MAX;
        distributor = IDividendDistributor(new DividendDistributor());

        _rOwned[msg.sender] = _rTotal;
        _isExcludedFromFee[msg.sender] = true;
        _isExcludedFromFee[address(this)] = true;
        _isExcludedFromDividend[address(this)] = true;
        _isExcludedFromDividend[pcsV2Pair] = true;
        _isExcludedFromDividend[address(0)] = true;

        marketingFeeReceiver = msg.sender;

        emit Transfer(address(0), msg.sender, _tTotal);
    }

    receive() external payable {}

    fallback() external payable {}


    //  -----------------------------
    //  SETTERS (PROTECTED)
    //  -----------------------------


    function excludeFromReward(address account) public onlyOwner {
        _excludeFromReward(account);
    }

    function includeInReward(address account) external onlyOwner {
        _includeInReward(account);
    }

    function setIsExcludedFromFee(address account, bool flag) external onlyOwner {
        _setIsExcludedFromFee(account, flag);
    }

    function setIsExcludedFromDividend (address account, bool flag) external onlyOwner {
        _setIsExcludedFromDividend(account, flag);
    }

    function setDistributorSettings(uint256 gas) external onlyOwner {
        distributorGas = gas;
    }

    function changeMinAmountForReward(uint256 amount) external onlyOwner {
        minTokenAmountForGetReward = amount * (10 ** _DECIMALS);
    }

    function changeFeesForNormalBuy(
        uint256 _liquidityFeeOnBuy,
        uint256 _BNBreflectionFeeOnBuy,
        uint256 _marketingFeeOnBuy,
        uint256 _HuHdistributionFeeOnBuy
    ) external onlyOwner {
        liquidityFeeOnBuy = _liquidityFeeOnBuy;
        BNBreflectionFeeOnBuy = _BNBreflectionFeeOnBuy;
        marketingFeeOnBuy = _marketingFeeOnBuy;
        HuHdistributionFeeOnBuy = _HuHdistributionFeeOnBuy;
    }

    function changeFeesForWhiteListedBuy_1_RefererOnly(
        uint256 _liquidityFeeOnBuy,
        uint256 _BNBFeeOnBuy,
        uint256 _marketingFeeOnBuy,
        uint256 _HuHdistributionFeeOnBuy
    ) external onlyOwner {
        liquidityFeeOnBuyWhiteListed_A = _liquidityFeeOnBuy;
        BNBrewardFor1stPerson_A = _BNBFeeOnBuy;
        marketingFeeOnBuyWhiteListed_A = _marketingFeeOnBuy;
        HuHdistributionFeeOnBuyWhiteListed_A = _HuHdistributionFeeOnBuy;
    }

    function changeFeesForWhiteListedBuy_2_Referers(
        uint256 _liquidityFeeOnBuy,
        uint256 _BNB1stPersonFeeOnBuy,
        uint256 _BNB2ndPersonFeeOnBuy,
        uint256 _marketingFeeOnBuy,
        uint256 _HuHdistributionFeeOnBuy
    ) external onlyOwner {
        liquidityFeeOnBuyWhiteListed_B = _liquidityFeeOnBuy;
        BNBrewardFor1stPerson_B = _BNB1stPersonFeeOnBuy;
        BNBrewardFor2ndPerson_B = _BNB2ndPersonFeeOnBuy;
        marketingFeeOnBuyWhiteListed_B = _marketingFeeOnBuy;
        HuHdistributionFeeOnBuyWhiteListed_B = _HuHdistributionFeeOnBuy;
    }

    function changeFeesForNormalSell(
        uint256 _liquidityFeeOnSell,
        uint256 _BNBreflectionFeeOnSell,
        uint256 _marketingFeeOnSell,
        uint256 _HuHdistributionFeeOnSell
    ) external onlyOwner {
        liquidityFeeOnSell = _liquidityFeeOnSell;
        BNBreflectionFeeOnSell = _BNBreflectionFeeOnSell;
        marketingFeeOnSell = _marketingFeeOnSell;
        HuHdistributionFeeOnSell = _HuHdistributionFeeOnSell;
    }

    function changeFeesForWhitelistedSell(
        uint256 _liquidityFeeOnSellWhiteListed,
        uint256 _BNBreflectionFeeOnSellWhiteListed,
        uint256 _marketingFeeOnSellWhiteListed,
        uint256 _HuHdistributionFeeOnSellWhiteListed
    ) external onlyOwner {
        liquidityFeeOnSellWhiteListed = _liquidityFeeOnSellWhiteListed;
        BNBreflectionFeeOnSellWhiteListed = _BNBreflectionFeeOnSellWhiteListed;
        marketingFeeOnSellWhiteListed = _marketingFeeOnSellWhiteListed;
        HuHdistributionFeeOnSellWhiteListed = _HuHdistributionFeeOnSellWhiteListed;
    }

    function changeMarketingWallet(address marketingFeeReceiver_) external onlyOwner {
        require(marketingFeeReceiver_ != address(0), "Zero address not allowed!");
        marketingFeeReceiver = marketingFeeReceiver_;
    }

    function setRefCodeRegistrator(address refCodeRegistrator_) external onlyOwner {
        require(refCodeRegistrator_ != address(0), "setRefCodeRegistrator: Zero address not allowed!");
        refCodeRegistrator = refCodeRegistrator_;
    }

    function changeSwapThreshold(uint256 swapThreshold_) external onlyOwner {
        swapThreshold = swapThreshold_ * (10 ** _DECIMALS);
    }

    function registerCode(address account, string memory code) external {
        require(msg.sender == refCodeRegistrator || msg.sender == owner(), "Not autorized!");

        bytes memory code_ = bytes(code);
        require(code_.length > 0, "Invalid code!");
        require(referUserForCode[code_] == address(0), "Code already used!");

        _registerCode(account, code_);
    }


    //  -----------------------------
    //  SETTERS
    //  -----------------------------


    function whitelist(string memory refCode) external {
        bytes memory refCode_ = bytes(refCode);
        require(refCode_.length > 0, "Invalid code!");
        require(!isWhitelisted[msg.sender], "Already whitelisted!");
        require(referUserForCode[refCode_] != address(0), "Non used code!");
        require(referUserForCode[refCode_] != msg.sender, "Invalid code!");

        _whitelistWithRef(msg.sender, referUserForCode[refCode_]);
    }

    function registerCode(string memory code) external {
        bytes memory code_ = bytes(code);
        require(code_.length > 0, "Invalid code!");
        require(referUserForCode[code_] == address(0), "Code already used!");

        _registerCode(msg.sender, code_);
    }

    function transfer(address recipient, uint256 amount)
        public
        override
        returns (bool)
    {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function approve(address spender, uint256 amount)
        public
        override
        returns (bool)
    {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(
            sender,
            _msgSender(),
            _allowances[sender][_msgSender()].sub(
                amount,
                "BEP20: transfer amount exceeds allowance"
            )
        );
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue)
        public
        virtual
        returns (bool)
    {
        _approve(
            _msgSender(),
            spender,
            _allowances[_msgSender()][spender].add(addedValue)
        );
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue)
        public
        virtual
        returns (bool)
    {
        _approve(
            _msgSender(),
            spender,
            _allowances[_msgSender()][spender].sub(
                subtractedValue,
                "BEP20: decreased allowance below zero"
            )
        );
        return true;
    }


    //  -----------------------------
    //  GETTERS
    //  -----------------------------


    function name() public pure override returns (string memory) {
        return _NAME;
    }

    function symbol() public pure override returns (string memory) {
        return _SYMBOL;
    }

    function decimals() public pure override returns (uint8) {
        return _DECIMALS;
    }

    function totalSupply() public view override returns (uint256) {
        return _tTotal;
    }

    function balanceOf(address account) public view override returns (uint256) {
        if (_isExcluded[account])
            return _tOwned[account];

        return tokenFromReflection(_rOwned[account]);
    }

    function allowance(address owner, address spender)
        public
        view
        override
        returns (uint256)
    {
        return _allowances[owner][spender];
    }

    function isExcludedFromReward(address account) public view returns (bool) {
        return _isExcluded[account];
    }

    function totalFees() public view returns (uint256) {
        return _tFeeTotal;
    }

    function reflectionFromToken(uint256 tAmount)
        public
        view
        returns (uint256)
    {
        uint256 rAmount = tAmount.mul(_getRate());
        return rAmount;
    }

    function tokenFromReflection(uint256 rAmount)
        public
        view
        returns (uint256)
    {
        require(
            rAmount <= _rTotal,
            "Amount must be less than total reflections"
        );
        uint256 currentRate = _getRate();
        return rAmount.div(currentRate);
    }


    //  -----------------------------
    //  INTERNAL
    //  -----------------------------


    function _getRate() private view returns (uint256) {
        (uint256 rSupply, uint256 tSupply) = _getCurrentSupply();
        return rSupply.div(tSupply);
    }

    function _getCurrentSupply() private view returns (uint256, uint256) {
        uint256 rSupply = _rTotal;
        uint256 tSupply = _tTotal;
        for (uint256 i = 0; i < _excluded.length; i++) {
            if (_rOwned[_excluded[i]] > rSupply || _tOwned[_excluded[i]] > tSupply)
                return (_rTotal, _tTotal);

            rSupply = rSupply.sub(_rOwned[_excluded[i]]);
            tSupply = tSupply.sub(_tOwned[_excluded[i]]);
        }

        if (rSupply < _rTotal.div(_tTotal)) {
            return (_rTotal, _tTotal);
        }

        return (rSupply, tSupply);
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) private {
        require(owner != address(0), "BEP20: approve from the zero address");
        require(spender != address(0), "BEP20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) private {
        require(sender != address(0), "BEP20: transfer from the zero address");
        require(recipient != address(0), "BEP20: transfer to the zero address");
        require(amount > 0, "BEP20: Transfer amount must be greater than zero");

        if (_inSwap) {
            _basicTransfer(sender, recipient, amount);
            return;
        }

        if ((reward1stPerson != address(0)) && (rewardAmount[reward1stPerson] > 0)) {
            _swapAndSend(reward1stPerson, rewardAmount[reward1stPerson]);
            if ((reward2ndPerson != address(0)) && (rewardAmount[reward2ndPerson] > 0)) {
                _swapAndSend(reward2ndPerson, rewardAmount[reward2ndPerson]);
            }
            reward1stPerson = address(0);
            reward2ndPerson = address(0);
            rewardAmount[reward1stPerson] = 0;
            rewardAmount[reward2ndPerson] = 0;
        }

        if (_shouldSwapBack())
            _swapBack();

        if (_isExcludedFromFee[sender] || _isExcludedFromFee[recipient]) {
            _basicTransfer(sender, recipient, amount);
        } else {
            if (recipient == pcsV2Pair) {
                if (isWhitelisted[sender]) {
                    _whitelistedSell(sender, recipient, amount);
                } else {
                    _normalSell(sender, recipient, amount);
                }
            } else if (sender == pcsV2Pair) {
                if (isWhitelisted[recipient] && isFirstBuy[recipient]) {
                    _whitelistedBuy(sender, recipient, amount);
                    isFirstBuy[recipient] = false;
                } else {
                    _normalBuy(sender, recipient, amount);
                }
            } else {
                _basicTransfer(sender, recipient, amount);
            }
        }

        if (!_isExcludedFromDividend[sender])
            try distributor.setShare(sender, balanceOf(sender)) {} catch {}
        if (!_isExcludedFromDividend[recipient])
            try distributor.setShare(recipient, balanceOf(recipient)) {} catch {}

        if (balanceOf(sender) < minTokenAmountForGetReward && !_isExcluded[sender]) {
            _excludeFromReward(sender);
            _setIsExcludedFromDividend(sender, true);
        }

        if (balanceOf(recipient) >= minTokenAmountForGetReward && _isExcluded[recipient]) {
            _includeInReward(sender);
            _setIsExcludedFromDividend(recipient, false);
        }

        if (launchedAt > 0) {
            uint256 gas = distributorGas;
            require(gasleft() >= gas, "Out of gas, please increase gas limit and retry!");
            try distributor.process{gas:distributorGas}() {} catch {}
        }

        if (launchedAt == 0 && recipient == pcsV2Pair) {
            launchedAt = block.number;
        }
    }

    function _basicTransfer(address sender, address recipient, uint256 amount) private {
        uint256 rAmount = reflectionFromToken(amount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rAmount);
        _tOwned[sender] = _tOwned[sender].sub(amount);
        _tOwned[recipient] = _tOwned[recipient].add(amount);

        emit Transfer(sender, recipient, amount);
    }

    function _normalBuy(address sender, address recipient, uint256 amount) private {
        uint256 currentRate = _getRate();
        uint256 rAmount = amount.mul(currentRate);
        uint256 rBNBreflectionFee = amount.div(100).mul(BNBreflectionFeeOnBuy).mul(currentRate);
        uint256 rLiquidityFee = amount.div(100).mul(liquidityFeeOnBuy).mul(currentRate);
        uint256 rHuhdistributionFee = amount.div(100).mul(HuHdistributionFeeOnBuy).mul(currentRate);
        uint256 rMarketingFee = amount.div(100).mul(marketingFeeOnBuy).mul(currentRate);
        uint256 rTransferAmount = rAmount.sub(rBNBreflectionFee).sub(rLiquidityFee).sub(rHuhdistributionFee).sub(rMarketingFee);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);
        _rOwned[address(this)] = _rOwned[address(this)].add(rBNBreflectionFee).add(rLiquidityFee);
        _tOwned[sender] = _tOwned[sender].sub(amount);
        _tOwned[recipient] = _tOwned[recipient].add(rTransferAmount.div(currentRate));
        _tOwned[address(this)] = _tOwned[address(this)].add(rBNBreflectionFee.div(currentRate)).add(rLiquidityFee.div(currentRate));
        _liquidityAccumulated = _liquidityAccumulated.add(rLiquidityFee.div(currentRate));
        _rOwned[marketingFeeReceiver] = _rOwned[marketingFeeReceiver].add(rMarketingFee);
        _tOwned[marketingFeeReceiver] = _tOwned[marketingFeeReceiver].add(rMarketingFee.div(currentRate));

        emit Transfer(sender, recipient, rTransferAmount.div(currentRate));
        emit Transfer(sender, address(this), (rBNBreflectionFee.add(rLiquidityFee)).div(currentRate));
        emit Transfer(sender, marketingFeeReceiver, rMarketingFee.div(currentRate));

        _reflectFee(rHuhdistributionFee, rHuhdistributionFee.div(currentRate));
    }

    function _whitelistedBuy(address sender, address recipient, uint256 amount) private {
        if (referParent[referParent[recipient]] == address(0)) {
            uint256 currentRate = _getRate();
            uint256 rAmount = amount.mul(currentRate);
            uint256 rBNBreward1stPerson = amount.div(100).mul(BNBrewardFor1stPerson_A).mul(currentRate);
            uint256 rLiquidityFee = amount.div(100).mul(liquidityFeeOnBuyWhiteListed_A).mul(currentRate);
            uint256 rHuhdistributionFee = amount.div(100).mul(HuHdistributionFeeOnBuyWhiteListed_A).mul(currentRate);
            uint256 rMarketingFee = amount.div(100).mul(marketingFeeOnBuyWhiteListed_A).mul(currentRate);
            uint256 rTransferAmount = rAmount.sub(rBNBreward1stPerson).sub(rLiquidityFee).sub(rHuhdistributionFee).sub(rMarketingFee);
            _rOwned[sender] = _rOwned[sender].sub(rAmount);
            _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);
            _rOwned[address(this)] = _rOwned[address(this)].add(rBNBreward1stPerson).add(rLiquidityFee);
            _tOwned[sender] = _tOwned[sender].sub(amount);
            _tOwned[recipient] = _tOwned[recipient].add(rTransferAmount.div(currentRate));
            _tOwned[address(this)] = _tOwned[address(this)].add(rBNBreward1stPerson.div(currentRate)).add(rLiquidityFee.div(currentRate));
            reward1stPerson = referParent[recipient];
            rewardAmount[reward1stPerson] = rBNBreward1stPerson.div(currentRate);
            _liquidityAccumulated = _liquidityAccumulated.add(rLiquidityFee.div(currentRate));
            _rOwned[marketingFeeReceiver] = _rOwned[marketingFeeReceiver].add(rMarketingFee);
            _tOwned[marketingFeeReceiver] = _tOwned[marketingFeeReceiver].add(rMarketingFee.div(currentRate));

            emit Transfer(sender, recipient, rTransferAmount.div(currentRate));
            emit Transfer(sender, address(this), (rBNBreward1stPerson.add(rLiquidityFee)).div(currentRate));
            emit Transfer(sender, marketingFeeReceiver, rMarketingFee.div(currentRate));

            _reflectFee(rHuhdistributionFee, rHuhdistributionFee.div(currentRate));
        } else {
            uint256 currentRate = _getRate();
            uint256 rAmount = amount.mul(currentRate);
            uint256 rBNBreward1stPerson = amount.div(100).mul(BNBrewardFor1stPerson_B).mul(currentRate);
            uint256 rBNBreward2ndPerson = amount.div(100).mul(BNBrewardFor2ndPerson_B).mul(currentRate);
            uint256 rLiquidityFee = amount.div(100).mul(liquidityFeeOnBuyWhiteListed_B).mul(currentRate);
            uint256 rHuhdistributionFee = amount.div(100).mul(HuHdistributionFeeOnBuyWhiteListed_B).mul(currentRate);
            uint256 rMarketingFee = amount.div(100).mul(marketingFeeOnBuyWhiteListed_B).mul(currentRate);
            uint256 rTransferAmount = rAmount.sub(rBNBreward1stPerson);
            rTransferAmount = rTransferAmount.sub(rBNBreward2ndPerson).sub(rLiquidityFee).sub(rHuhdistributionFee).sub(rMarketingFee);
            _rOwned[sender] = _rOwned[sender].sub(rAmount);
            _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);
            _rOwned[address(this)] = _rOwned[address(this)].add(rBNBreward1stPerson).add(rBNBreward2ndPerson).add(rLiquidityFee);
            _tOwned[sender] = _tOwned[sender].sub(amount);
            _tOwned[recipient] = _tOwned[recipient].add(rTransferAmount.div(currentRate));
            _tOwned[address(this)] = _tOwned[address(this)].add(rBNBreward1stPerson.div(currentRate)).add(rBNBreward2ndPerson.div(currentRate)).add(rLiquidityFee.div(currentRate));
            reward1stPerson = referParent[recipient];
            reward2ndPerson = referParent[referParent[recipient]];
            rewardAmount[reward1stPerson] = rBNBreward1stPerson.div(currentRate);
            rewardAmount[reward2ndPerson] = rBNBreward2ndPerson.div(currentRate);
            _liquidityAccumulated = _liquidityAccumulated.add(rLiquidityFee.div(currentRate));
            _rOwned[marketingFeeReceiver] = _rOwned[marketingFeeReceiver].add(rMarketingFee);
            _tOwned[marketingFeeReceiver] = _tOwned[marketingFeeReceiver].add(rMarketingFee.div(currentRate));

            emit Transfer(sender, recipient, rTransferAmount.div(currentRate));
            emit Transfer(sender, address(this), (rBNBreward1stPerson.add(rBNBreward2ndPerson).add(rLiquidityFee)).div(currentRate));
            emit Transfer(sender, marketingFeeReceiver, rMarketingFee.div(currentRate));

            _reflectFee(rHuhdistributionFee, rHuhdistributionFee.div(currentRate));
        }
    }

    function _normalSell(address sender, address recipient, uint256 amount) private {
        uint256 currentRate = _getRate();
        uint256 rAmount = amount.mul(currentRate);
        uint256 rBNBreflectionFee = amount.div(100).mul(BNBreflectionFeeOnSell).mul(currentRate);
        uint256 rLiquidityFee = amount.div(100).mul(liquidityFeeOnSell).mul(currentRate);
        uint256 rHuhdistributionFee = amount.div(100).mul(HuHdistributionFeeOnSell).mul(currentRate);
        uint256 rMarketingFee = amount.div(100).mul(marketingFeeOnSell).mul(currentRate);
        uint256 rTransferAmount = rAmount.sub(rBNBreflectionFee).sub(rLiquidityFee).sub(rHuhdistributionFee).sub(rMarketingFee);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);
        _rOwned[address(this)] = _rOwned[address(this)].add(rBNBreflectionFee).add(rLiquidityFee);
        _tOwned[sender] = _tOwned[sender].sub(amount);
        _tOwned[recipient] = _tOwned[recipient].add(rTransferAmount.div(currentRate));
        _tOwned[address(this)] = _tOwned[address(this)].add(rBNBreflectionFee.div(currentRate)).add(rLiquidityFee.div(currentRate));
        _liquidityAccumulated = _liquidityAccumulated.add(rLiquidityFee.div(currentRate));
        _rOwned[marketingFeeReceiver] = _rOwned[marketingFeeReceiver].add(rMarketingFee);
        _tOwned[marketingFeeReceiver] = _tOwned[marketingFeeReceiver].add(rMarketingFee.div(currentRate));

        emit Transfer(sender, recipient, rTransferAmount.div(currentRate));
        emit Transfer(sender, address(this), (rBNBreflectionFee.add(rLiquidityFee)).div(currentRate));
        emit Transfer(sender, marketingFeeReceiver, rMarketingFee.div(currentRate));

        _reflectFee(rHuhdistributionFee, rHuhdistributionFee.div(currentRate));
    }

    function _whitelistedSell(address sender, address recipient, uint256 amount) private {
        uint256 currentRate = _getRate();
        uint256 rAmount = amount.mul(currentRate);
        uint256 rBNBreflectionFee = amount.div(100).mul(BNBreflectionFeeOnSellWhiteListed).mul(currentRate);
        uint256 rLiquidityFee = amount.div(100).mul(liquidityFeeOnSellWhiteListed).mul(currentRate);
        uint256 rHuhdistributionFee = amount.div(100).mul(HuHdistributionFeeOnSellWhiteListed).mul(currentRate);
        uint256 rMarketingFee = amount.div(100).mul(marketingFeeOnSellWhiteListed).mul(currentRate);
        uint256 rTransferAmount = rAmount.sub(rBNBreflectionFee).sub(rLiquidityFee).sub(rHuhdistributionFee).sub(rMarketingFee);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);
        _rOwned[address(this)] = _rOwned[address(this)].add(rBNBreflectionFee).add(rLiquidityFee);
        _tOwned[sender] = _tOwned[sender].sub(amount);
        _tOwned[recipient] = _tOwned[recipient].add(rTransferAmount.div(currentRate));
        _tOwned[address(this)] = _tOwned[address(this)].add(rBNBreflectionFee.div(currentRate)).add(rLiquidityFee.div(currentRate));
        _liquidityAccumulated = _liquidityAccumulated.add(rLiquidityFee.div(currentRate));
        _rOwned[marketingFeeReceiver] = _rOwned[marketingFeeReceiver].add(rMarketingFee);
        _tOwned[marketingFeeReceiver] = _tOwned[marketingFeeReceiver].add(rMarketingFee.div(currentRate));

        emit Transfer(sender, recipient, rTransferAmount.div(currentRate));
        emit Transfer(sender, address(this), (rBNBreflectionFee.add(rLiquidityFee)).div(currentRate));
        emit Transfer(sender, marketingFeeReceiver, rMarketingFee.div(currentRate));

        _reflectFee(rHuhdistributionFee, rHuhdistributionFee.div(currentRate));
    }

    function _swapAndSend(address recipient, uint256 amount) private swapping {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = pcsV2Router.WETH();

        pcsV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            amount,
            0,
            path,
            recipient,
            block.timestamp
        );
    }

    function _shouldSwapBack() private view returns (bool) {
        return msg.sender != pcsV2Pair
            && launchedAt > 0
            && !_inSwap
            && swapEnabled
            && balanceOf(address(this)) >= swapThreshold;
    }

    function _swapBack() private swapping {
        uint256 amountToSwap = _liquidityAccumulated.div(2);

        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = pcsV2Router.WETH();

        uint256 balanceBefore = address(this).balance;

        pcsV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            amountToSwap,
            0,
            path,
            address(this),
            block.timestamp
        );

        uint256 differenceBnb = address(this).balance.sub(balanceBefore);

        pcsV2Router.addLiquidityETH{value: differenceBnb}(
            address(this),
            amountToSwap,
            0,
            0,
            _DEAD_ADDRESS,
            block.timestamp
        );

        emit SwapAndLiquify(differenceBnb, amountToSwap);

        amountToSwap = balanceOf(address(this));
        pcsV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            amountToSwap,
            0,
            path,
            address(this),
            block.timestamp
        );

        _liquidityAccumulated = 0;

        differenceBnb = address(this).balance;
        try distributor.deposit{value: differenceBnb}() {} catch {}
    }

    function _reflectFee(uint256 rFee, uint256 tFee) private {
        _rTotal = _rTotal.sub(rFee);
        _tFeeTotal = _tFeeTotal.add(tFee);
    }

    function _excludeFromReward(address account) private {
        // require(account != 0x10ED43C718714eb63d5aA57B78B54704E256024E, 'We can not exclude PancakeSwap router.');
        require(!_isExcluded[account], "Account is already excluded");

        if (_rOwned[account] > 0) {
            _tOwned[account] = tokenFromReflection(_rOwned[account]);
        }
        _isExcluded[account] = true;
        _excluded.push(account);
    }

    function _includeInReward(address account) private {
        require(_isExcluded[account], "Account is already included");
        for (uint256 i = 0; i < _excluded.length; i++) {
            if (_excluded[i] == account) {
                _excluded[i] = _excluded[_excluded.length - 1];
                _rOwned[account] = reflectionFromToken(_tOwned[account]);
                _tOwned[account] = 0;
                _isExcluded[account] = false;
                _excluded.pop();
                break;
            }
        }
    }

    function _setIsExcludedFromFee(address account, bool flag) private {
        _isExcludedFromFee[account] = flag;
    }

    function _setIsExcludedFromDividend(address account, bool flag) private {
        _isExcludedFromDividend[account] = flag;
    }

    function _whitelistWithRef(address account, address referee) private {
        isFirstBuy[account] = true;
        isWhitelisted[msg.sender] = true;
        referParent[msg.sender] = referee;

        emit UserWhitelisted(account, referee);
    }

    function _registerCode(address account, bytes memory code) private {
        referUserForCode[code] = account;
        referCodeForUser[account] = code;

        emit CodeRegisterred(account, code);
    }
}