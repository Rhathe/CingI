package missions

import (
	"log"
	"gopkg.in/yaml.v2"
)

type Mission struct {
	Name string
	subMissions []Mission
	SubMissionStrings []string `yaml:"subMissions"`
}

func NewMission(data []byte) *Mission {
	m := Mission{}
	err := yaml.Unmarshal(data, &m)

	if err != nil {
		log.Fatalf("error: %v", err)
	}

	return &m
}

func (m *Mission) ToYaml() string {
	d, err := yaml.Marshal(m)

	if err != nil {
		log.Fatalf("error: %v", err)
	}

	return string(d)
}
