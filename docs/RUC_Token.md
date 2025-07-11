# 🗃️ RUC Token 合约技术说明文档

## 📌 合约概述

`RUC` 是一个兼容 BEP-20 的代币合约，部署于 BNB Chain，具备交易税收，白名单控制买入，自动清除 LP pool 部分水量（通过 `poolDeflation`），其主要特性包括：

- PancakeSwap 交易对自动创建
- 收取交易税（最大 20%，默认 15%），并转给指定 taxWallet
- 支持白名单控制的买入策略
- 支持用户销毁和合约自动销毁 poolToken
- owner 可设置免税地址，不受 tax 影响

---

## ⚙️ 核心参数

| 变量          | 含义                                 |
| ------------- | ------------------------------------ |
| `name`        | Token 名称：RUC                      |
| `symbol`      | Token 符号：RUC                      |
| `decimals`    | 精度：18                             |
| `totalSupply` | 总量：1 万亿 RUC (1,000,000,000,000) |
| `taxPercent`  | 交易税：15%（可设置）                |
| `buyEnabled`  | 是否允许买入（可禁止买入）           |
| `taxWallet`   | 收税地址                             |
| `pancakePair` | 交易对地址                           |
| `isTaxExempt` | 免税地址列表                         |
| `isWhitelist` | 允许买入白名单                       |

---

## 🔄 核心功能逻辑

### 1. 初始化

- 部署者自动成为 `owner`，同时设置 `taxWallet`
- 创建和自己与 RG Token 的交易对
- 100%代币分配给 owner

### 2. 转账 / 授权 / 授权转账

- 基本 BEP-20 功能：`transfer` 、`approve` 、`transferFrom`
- 使用 `_transfer` 全局逻辑：检查税，配置免税、允许白名单

### 3. 交易税功能

- 卖出（to = pancakePair）或买入（from = pancakePair）时都可以收税
- 免税地址不展示税收
- 所得税入 `taxWallet`，触发 `FeeReceived`

### 4. 买入管控

- 如果启用 `buyEnabled = false`，则仅有白名单地址可以买入
- 白名单通过 `setBuyWhitelist` 配置

### 5. burn

- 用户可以自行 burn 自己的 RUC
- 合约支持一个 `poolDeflation`，以销毁交易对中的 token，并通知 pair 合约 sync
- 销毁量 = pair 余额的 2%

---

## 🔐 Owner 权限

- `setTaxWallet`：设置收税地址
- `setTaxExempt`：设置免税地址
- `setBuyEnabled`：禁止/允许买入
- `setBuyWhitelist`：白名单设置
- `setTaxPercent`：税率设置，最大 20%
- `setPancakePair`：手动设置交易对
- `transferOwnership`：转移 owner
- `poolDeflation`：自动销毁交易对余额 2%

---

## 📊 事件

- `Transfer`：标准 BEP20 事件
- `Approval`：授权事件
- `OwnershipTransferred`：owner 转移事件
- `FeeReceived`：收税时触发
- `PoolDeflated`：自动销毁事件
