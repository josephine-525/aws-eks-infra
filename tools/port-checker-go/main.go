// port-checker concurrently checks whether a list of host:port targets accept
// a TCP connection -- the same shape of tool the user described building
// years ago (validate a list of IPs/URLs, check whether a port is open).
package main

import (
	"fmt"
	"net"
	"sync"
	"time"
)

// A mix of real hosts on different ports, plus one deliberately unreachable
// target (an address in the TEST-NET-1 documentation range, RFC 5737 --
// guaranteed to never route anywhere) so you see a real timeout/failure too,
// not just a wall of green.
var targets = []string{
	"google.com:443",
	"github.com:443",
	"github.com:80",
	"cloudflare.com:443",
	"amazon.com:443",
	"1.1.1.1:443",
	"8.8.8.8:53",
	"golang.org:443",
	"stackoverflow.com:443",
	"wikipedia.org:443",
	"reddit.com:443",
	"microsoft.com:443",
	"apple.com:443",
	"netflix.com:443",
	"192.0.2.1:443", // TEST-NET-1 -- never routable, will time out on purpose
}

// result carries one target's outcome back from its goroutine. Bundling
// target+ok+err into a struct (rather than three separate channels) is what
// makes it possible to send everything over a single channel below.
type result struct {
	target string
	ok     bool
	err    error
}

// checkTarget is what each goroutine runs. It knows nothing about the other
// 14 targets being checked at the same time -- it just dials, and reports
// what happened onto the shared channel.
func checkTarget(target string, results chan<- result, wg *sync.WaitGroup) {
	defer wg.Done() // signal "I'm done" no matter which return path is taken

	conn, err := net.DialTimeout("tcp", target, 3*time.Second)
	if err != nil {
		results <- result{target: target, ok: false, err: err}
		return
	}
	conn.Close()
	results <- result{target: target, ok: true}
}

func main() {
	var wg sync.WaitGroup
	// Buffered with exactly len(targets) capacity: every goroutine can send
	// its result and return immediately, without blocking on a receiver
	// being ready at that exact moment. With an unbuffered channel here,
	// you'd need a receiver goroutine running concurrently with the senders
	// to avoid deadlock -- buffering sidesteps that.
	results := make(chan result, len(targets))

	start := time.Now()

	for _, t := range targets {
		wg.Add(1)
		go checkTarget(t, results, &wg)
	}

	// A goroutine to close the channel once every checkTarget has finished --
	// wg.Wait() blocks until all 15 call wg.Done(), then close(results)
	// lets the range loop below terminate instead of blocking forever.
	go func() {
		wg.Wait()
		close(results)
	}()

	var okCount, failCount int
	for r := range results {
		if r.ok {
			okCount++
			fmt.Printf("OK    %s\n", r.target)
		} else {
			failCount++
			fmt.Printf("FAIL  %s (%v)\n", r.target, r.err)
		}
	}

	elapsed := time.Since(start)
	fmt.Printf("\n%d ok, %d failed, %d total -- %s\n", okCount, failCount, len(targets), elapsed)
}
