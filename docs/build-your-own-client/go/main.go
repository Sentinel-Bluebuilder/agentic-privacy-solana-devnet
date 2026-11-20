// Command byoc reads the dvpn program on devnet with the public Go SDK and,
// given a key file and a node, builds an open_channel transaction and SIMULATES it.
//
// Usage: go run . [keypair.json nodeAddress escrowBaseUnits]
package main

import (
	"context"
	"crypto/rand"
	"fmt"
	"log"
	"os"
	"strconv"
	"time"

	"github.com/solana-foundation/solana-go/v2"
	"github.com/solana-foundation/solana-go/v2/rpc"

	"github.com/sentinel-official/sentinel-go-sdk/v3/program"
	"github.com/sentinel-official/sentinel-programs/clients/go/dvpn"
)

// ─── Devnet constants ───
var (
	programID = solana.MustPublicKeyFromBase58("J52dyXW3a6mkatvrQct3fo6dA9vqUtcsdBt5gGqrTBXs")
	mint      = solana.MustPublicKeyFromBase58("Hen2LVP6KooGaXEvdSyCHWghsEY4gLLn7wix8z6zHFSa")
)

func main() {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()

	// The generated client ships with a placeholder program id; point it at devnet.
	if err := dvpn.SetProgramID(programID); err != nil {
		log.Fatalf("set program id: %v", err)
	}
	rpcClient := rpc.New(rpc.DevNet_RPC)
	client := program.NewClient(rpcClient, programID, mint, rpc.CommitmentConfirmed)

	// ─── Read: config + live nodes ───
	if err := client.CheckMint(ctx); err != nil {
		log.Fatalf("check mint: %v", err)
	}
	cfg, err := client.Config(ctx)
	if err != nil {
		log.Fatalf("config: %v", err)
	}
	fmt.Printf("config: mint %s decimals %d fee_bps %d close_grace %ds listing_ttl %ds paused_mask %d\n",
		cfg.Mint, cfg.Decimals, cfg.FeeBps, cfg.ChannelCloseGraceSeconds, cfg.NodeListingTTLSeconds, cfg.PausedMask)

	nodes, err := client.FindNodeAccounts(ctx, dvpn.NodeFilter())
	if err != nil {
		log.Fatalf("nodes: %v", err)
	}
	now := time.Now().Unix()
	live := 0
	for _, n := range nodes {
		if n.Value.Status == dvpn.ListingStatusListed && program.Live(n.Value, cfg, now) {
			if live < 3 {
				fmt.Printf("  %s %s %s per_gb=%d per_hour=%d\n", n.Address, string(n.Value.Country[:]),
					program.NodeURI(n.Value), n.Value.ChannelPricePerGB, n.Value.ChannelPricePerHour)
			}
			live++
		}
	}
	fmt.Printf("nodes: %d accounts, %d listed and live\n", len(nodes), live)

	if len(os.Args) < 4 {
		return
	}

	// ─── Write: build open_channel, simulate only ───
	key, err := solana.PrivateKeyFromSolanaKeygenFile(os.Args[1])
	if err != nil {
		log.Fatalf("key: %v", err)
	}
	owner := key.PublicKey()
	node := solana.MustPublicKeyFromBase58(os.Args[2])
	escrow, err := strconv.ParseUint(os.Args[3], 10, 64)
	if err != nil {
		log.Fatalf("escrow: %v", err)
	}
	var channelID [32]uint8
	if _, err := rand.Read(channelID[:]); err != nil {
		log.Fatalf("channel id: %v", err)
	}
	ownerToken, err := client.AssociatedTokenAddress(owner)
	if err != nil {
		log.Fatalf("ata: %v", err)
	}
	ix, err := dvpn.BuildOpenChannelInstruction(programID, dvpn.OpenChannelParams{
		ChannelID:            channelID,
		Escrow:               escrow,
		Terms:                &dvpn.PositionTermsVoucher{VoucherSigner: owner},
		ChannelRentRecipient: owner, // must be the signer or the rent payer
		UserRentRecipient:    owner,
		Signer:               owner,
		Owner:                owner,
		Grant:                nil, // owner signs itself: no grant
		Node:                 node,
		Vault:                cfg.Vault,
		Mint:                 mint,
		OwnerToken:           ownerToken,
		RentPayer:            owner,
	})
	if err != nil {
		log.Fatalf("build: %v", err)
	}
	channel, _, _ := dvpn.FindChannelAddress(programID, owner, channelID)
	recent, err := rpcClient.GetLatestBlockhash(ctx, rpc.CommitmentConfirmed)
	if err != nil {
		log.Fatalf("blockhash: %v", err)
	}
	tx, err := solana.NewTransaction([]solana.Instruction{ix}, recent.Value.Blockhash, solana.TransactionPayer(owner))
	if err != nil {
		log.Fatalf("tx: %v", err)
	}
	if _, err := tx.Sign(func(pk solana.PublicKey) *solana.PrivateKey {
		if pk.Equals(owner) {
			return &key
		}
		return nil
	}); err != nil {
		log.Fatalf("sign: %v", err)
	}
	sim, err := rpcClient.SimulateTransaction(ctx, tx)
	if err != nil {
		log.Fatalf("simulate: %v", err)
	}
	fmt.Printf("open_channel %s simulate: err=%v units=%d\n", channel, sim.Value.Err, derefU64(sim.Value.UnitsConsumed))
	if sim.Value.Err != nil {
		for _, l := range sim.Value.Logs {
			fmt.Println("  ", l)
		}
		os.Exit(1)
	}
}

func derefU64(v *uint64) uint64 {
	if v == nil {
		return 0
	}
	return *v
}
