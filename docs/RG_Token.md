# 💼 RG Token 合约技术说明文档

## 📌 合约概述

`RG` 是一个兼容 BEP-20 的代币合约，部署在 BNB Chain 上，具备如下特性：

- 支持 PancakeSwap 交易对创建；
- 在卖出行为上收取交易税（最高 20%）；
- 可控制买入权限（白名单模式）；
- 支持地址免税设置；
- 支持地址间转账、授权、销毁（burn）；
- 所有敏感操作均需合约 owner 权限。

---

## ⚙️ 核心参数

| 变量名        | 含义                   |
| ------------- | ---------------------- |
| `name`        | Token 名称（RG）       |
| `symbol`      | Token 符号（RG）       |
| `decimals`    | 精度（18 位）          |
| `totalSupply` | 初始总发行量（1 亿枚） |
| `owner`       | 合约拥有者地址         |
| `taxWallet`   | 收税地址               |
| `pancakePair` | 交易对地址             |
| `router`      | PancakeSwap 路由地址   |

---

## 🔄 核心逻辑

### 1. ✅ 初始化（constructor）

- 接收 PancakeRouter 地址 `_router` 和 USDT 地址 `usdtToken`；
- 创建交易对（`createPair(usdtToken, address(this))`）；
- 设置 owner、router、taxWallet 均为部署者；
- 100% 的初始供应量分配给部署者。

---

### 2. ✅ 转账函数（`transfer`, `transferFrom`, `_transfer`）

- 基础 BEP20 转账逻辑；
- 当转出地址或接收地址非免税地址，且接收地址为 `pancakePair`（即卖出时），将收取 `taxPercent` 的税；
- 所得税转入 `taxWallet`；
- 买入时（from 为交易对地址），若 `buyEnabled == false`，仅允许 `isWhitelist` 中的地址买入；
- 支持授权转账（`approve`, `transferFrom`）。

---

### 3. 💰 税收机制

- 默认税率为 20%（最大支持 20%）；
- 仅在卖出（即 to 为 `pancakePair`）时收取；
- 可通过 `setTaxExempt` 设置地址是否免税；
- 收取的税将转入 `taxWallet`；
- `FeeReceived` 事件记录收税信息。

---

### 4. 🛡️ 交易控制（买入限制）

- 可启用/禁用买入（`setBuyEnabled`）；
- 当买入禁用时，只有白名单地址（`isWhitelist`）可以买入；
- 白名单由 `setBuyWhitelist` 管理。

---

### 5. 🔥 销毁逻辑（`burn`, `_burn`）

- 用户可自行销毁手中的 token；
- 销毁会减少该账户余额以及 `totalSupply`；
- 触发标准 Transfer 事件（to = `address(0)`）。

---

### 6. 🔐 管理权限（`onlyOwner`）

合约中的以下操作仅合约 owner 可以执行：

| 函数                | 描述               |
| ------------------- | ------------------ |
| `setTaxWallet`      | 设置税收地址       |
| `setTaxExempt`      | 设置免税地址       |
| `setBuyEnabled`     | 设置是否启用买入   |
| `setBuyWhitelist`   | 设置买入白名单     |
| `setTaxPercent`     | 设置税率（<= 20%） |
| `setPancakePair`    | 手动设置交易对地址 |
| `transferOwnership` | 转移合约所有权     |

---

## 📊 事件说明

| 事件名                 | 说明                                     |
| ---------------------- | ---------------------------------------- |
| `Transfer`             | 标准 BEP20 事件                          |
| `Approval`             | 标准 BEP20 授权事件                      |
| `OwnershipTransferred` | owner 转移事件                           |
| `FeeReceived`          | 税费收取事件，包含收税地址、发送方与金额 |

---

## ✅ 标准兼容性

- 合约基本兼容 BEP-20/ERC-20 标准接口；
- 事件与函数签名与主流钱包兼容；
- 可无缝集成 PancakeSwap 前端及其他 DEX。
