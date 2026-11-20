module byoc

go 1.27.3

require (
	github.com/sentinel-official/sentinel-go-sdk/v3 v3.0.0
	github.com/sentinel-official/sentinel-programs/clients/go v0.0.0
)

// Point both modules at a clone of the public monorepo
// (github.com/sentinel-official/sentinel-solana at 26de5240), cloned to ../ss.
replace (
	github.com/sentinel-official/sentinel-go-sdk/v3 => ../ss/sentinel-go-sdk
	github.com/sentinel-official/sentinel-programs/clients/go => ../ss/sentinel-programs/clients/go
)
