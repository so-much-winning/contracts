package main

import (
	"context"
	"errors"
	"io/ioutil"
	"log"
	"os"

	"github.com/ethereum/go-ethereum/accounts/abi/bind"
	"github.com/ethereum/go-ethereum/accounts/keystore"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/contracts/ens"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/ethclient"
	hdwallet "github.com/miguelmota/go-ethereum-hdwallet"
	"github.com/sirupsen/logrus"
	"github.com/tyler-smith/go-bip39"
	"gopkg.in/urfave/cli.v1"
)

// Running test chain: docker run --rm -p 8545:8545 parity/parity:v2.4.6 --config dev --jsonrpc-interface=0.0.0.0 --jsonrpc-port=8545

func main() {
	app := cli.NewApp()

	app.Name = "deploy"
	app.Usage = "deploy infrastructure contracts to an ethereum network"

	app.Flags = []cli.Flag{
		cli.StringFlag{
			Name:   "ethereum",
			Usage:  "Ethereum node's address.",
			EnvVar: "ETHEREUM_ADDRESS",
			Value:  "http://localhost:8545",
		},
		cli.StringFlag{
			Name:   "ens-address",
			Usage:  "Ethereum name service contract address.",
			EnvVar: "ENS_ADDRESS",
		},
		cli.StringFlag{
			Name:   "ens-resolver-address",
			Usage:  "Tokencard's ENS resolver address.",
			EnvVar: "ENS_RESOLVER_ADDRESS",
		},
		cli.StringFlag{
			Name:   "oraclize-resolver-address",
			Usage:  "Oraclize resolver address.",
			EnvVar: "ORACLIZE_RESOLVER_ADDRESS",
			Value:  "0x1",
		},
		cli.StringFlag{
			Name:   "key-file",
			Usage:  "JSON key file location.",
			EnvVar: "KEY_FILE",
			Value:  "dev.key.json",
		},
		cli.StringFlag{
			Name:   "key-mnemonic",
			Usage:  "Mnemonic (BIP 39) to derive the key.",
			EnvVar: "KEY_MNEMONIC",
			Value:  "",
		},
		cli.StringFlag{
			Name:   "passphrase",
			Usage:  "Keystore file passphrase.",
			EnvVar: "PASSPHRASE",
			Value:  "",
		},
	}

	app.Action = run

	app.Commands = []cli.Command{
		cli.Command{
			Name:   "deploy-ens",
			Action: deployENS,
			Flags: []cli.Flag{
				cli.StringFlag{
					Name:   "ethereum",
					Usage:  "Ethereum node's address.",
					EnvVar: "ETHEREUM_ADDRESS",
					Value:  "http://localhost:8545",
				},
				cli.StringFlag{
					Name:   "key-file",
					Usage:  "JSON key file location.",
					EnvVar: "KEY_FILE",
					Value:  "dev.key.json",
				},
				cli.StringFlag{
					Name:   "passphrase",
					Usage:  "Keystore file passphrase.",
					EnvVar: "PASSPHRASE",
					Value:  "",
				},
			},
		},
	}

	err := app.Run(os.Args)
	if err != nil {
		log.Fatal(err)
	}

}

func deployENS(c *cli.Context) error {
	keyJSON, err := ioutil.ReadFile(c.String("key-file"))
	if err != nil {
		return err
	}

	decrypted, err := keystore.DecryptKey(keyJSON, c.String("passphrase"))
	if err != nil {
		return err
	}

	ec, err := ethclient.Dial(c.String("ethereum"))
	if err != nil {
		return err
	}

	defer ec.Close()

	txOpt := &bind.TransactOpts{
		Signer: func(signer types.Signer, addr common.Address, tx *types.Transaction) (*types.Transaction, error) {
			return types.SignTx(tx, signer, decrypted.PrivateKey)
		},
		From: decrypted.Address,
	}

	d := &deployer{
		transactOpts:    txOpt,
		controllerOwner: decrypted.Address,
		ctx:             context.Background(),
		ethClient:       ec,
		log:             logrus.New(),
	}

	return d.deployENS()

}

func run(c *cli.Context) error {

	var txOpt *bind.TransactOpts

	if c.IsSet("key-mnemonic") {

		logrus.Info("using provided mnemonic")

		mnemonic := c.String("key-mnemonic")
		seed := bip39.NewSeed(mnemonic, "")

		wallet, err := hdwallet.NewFromSeed(seed)
		if err != nil {
			return err
		}

		path, err := hdwallet.ParseDerivationPath("m/44'/60'/0'/0/0")
		if err != nil {
			return err
		}

		account, err := wallet.Derive(path, false)
		if err != nil {
			return err
		}

		txOpt = &bind.TransactOpts{
			Signer: func(signer types.Signer, addr common.Address, tx *types.Transaction) (*types.Transaction, error) {
				pk, err := wallet.PrivateKey(account)
				if err != nil {
					return nil, err
				}
				return types.SignTx(tx, signer, pk)
			},
			From: account.Address,
		}
	} else if c.IsSet("key-file") {

		logrus.Infof("using keystore at %s", c.String("key-file"))

		keyJSON, err := ioutil.ReadFile(c.String("key-file"))
		if err != nil {
			return err
		}

		decrypted, err := keystore.DecryptKey(keyJSON, c.String("passphrase"))
		if err != nil {
			return err
		}

		txOpt = &bind.TransactOpts{
			Signer: func(signer types.Signer, addr common.Address, tx *types.Transaction) (*types.Transaction, error) {
				return types.SignTx(tx, signer, decrypted.PrivateKey)
			},
			From: decrypted.Address,
		}

	} else {
		return errors.New("neither key file nor key mnemonic used")
	}

	ec, err := ethclient.Dial(c.String("ethereum"))
	if err != nil {
		return err
	}

	defer ec.Close()

	ensAddress := common.HexToAddress(c.String("ens-address"))

	logrus.Info("using ENS address", ensAddress.Hex())
	logrus.Info("sending from  address", txOpt.From.Hex())

	en, err := ens.NewENS(txOpt, ensAddress, ec)
	if err != nil {
		return err
	}

	d := &deployer{
		transactOpts:            txOpt,
		ens:                     en,
		ensAddress:              ensAddress,
		controllerOwner:         txOpt.From,
		ctx:                     context.Background(),
		ethClient:               ec,
		log:                     logrus.New(),
		oraclizeResolverAddress: common.HexToAddress(c.String("oraclize-resolver-address")),
	}

	err = d.deployController()
	if err != nil {
		return err
	}

	// TODO deploy oracle - needs fixing, ATM it's failing
	// err = d.deployOracle()
	// if err != nil {
	// 	return err
	// }

	err = d.deployWalletDeployer()
	if err != nil {
		return err
	}

	return nil
}