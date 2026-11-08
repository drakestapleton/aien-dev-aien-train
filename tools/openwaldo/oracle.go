// Test-only upstream interoperability oracle. Never linked into the Omega product.
package main

import (
 "bytes"
 "encoding/json"
 "fmt"
 "os"
 "github.com/openwaldo/waldo/internal/record"
)
func main() {
 raw, err := os.ReadFile(os.Args[1]); if err != nil { panic(err) }
 var in struct { SHA256 string `json:"sha256"`; Kind string `json:"kind"`; Text string `json:"text"`; Source string `json:"source"`; License string `json:"license"`; Meta json.RawMessage `json:"meta"` }
 if err := json.Unmarshal(raw, &in); err != nil { panic(err) }
 r := record.Record{SHA256:in.SHA256, Kind:in.Kind, Text:in.Text, Source:in.Source, License:in.License}
 canonical, err := r.AppendCanonical(nil, in.Meta); if err != nil { panic(err) }
 if !bytes.Equal(raw, canonical) { panic("not byte-identical to pinned upstream canonical record writer") }
 fmt.Println("PASS pinned OpenWALDO Record.Validate and AppendCanonical exact-byte oracle")
}
