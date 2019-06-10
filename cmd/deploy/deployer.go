package main

import (
	"context"
	"time"

	"github.com/ethereum/go-ethereum/accounts/abi/bind"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/contracts/ens"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/ethclient"
	"github.com/pkg/errors"
	"github.com/sirupsen/logrus"
)

type deployer struct {
	transactOpts *bind.TransactOpts
	ethClient    *ethclient.Client
	ens          *ens.ENS

	ensAddress         common.Address
	ensResolverAddress common.Address

	log                     logrus.FieldLogger
	controllerOwner         common.Address
	ctx                     context.Context
	oraclizeResolverAddress common.Address
}

var zeroAddress = common.HexToAddress("0x0")

const waitForMiningTimeout = 2 * 60 * time.Second

func (d *deployer) waitForTransactionToBeMined(txHash common.Hash) error {
	ctx, cancel := context.WithTimeout(d.ctx, waitForMiningTimeout)
	defer cancel()

	for {
		var pending bool
		_, pending, err := d.ethClient.TransactionByHash(ctx, txHash)
		if err != nil {
			return errors.Wrapf(err, "while getting transaction status of %s", txHash.Hex())
		}

		if !pending {
			break
		}

		time.Sleep(time.Second)
	}

	return nil
}

func (d *deployer) ensureTransactionSuccess(txHash common.Hash) error {
	rcpt, err := d.ethClient.TransactionReceipt(d.ctx, txHash)
	if err != nil {
		return err
	}

	if rcpt.Status != types.ReceiptStatusSuccessful {
		return errors.Errorf("transaction %s failed", txHash.Hex())
	}

	return nil

}

func (d *deployer) waitForAndConfirmTransaction(txHash common.Hash) error {
	err := d.waitForTransactionToBeMined(txHash)
	if err != nil {
		return err
	}
	return d.ensureTransactionSuccess(txHash)
}