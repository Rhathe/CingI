package main

import (
	"fmt"
	"c-ing-i/missions"
)

var data = `
name: test
`

func main() {
	m := missions.NewMission([]byte(data))

	fmt.Println(m.Name)

	d := m.ToYaml()

	fmt.Println(d)
}
