package missions

import (
	"log"
	"gopkg.in/yaml.v2"
)

type MissionReport struct {
	Message string
}

type SubMission struct {
	RunType string
	Command string
	Mission Mission
}

type Mission struct {
	Name string

	SubMissions []SubMission
	parallel []SubMission
	serial []SubMission
	beforeAll []SubMission
	beforeEach []SubMission
	afterAll []SubMission
	afterEach []SubMission

	subMissionReports []MissionReport

	upstream chan MissionReport
	downstream chan MissionReport

	subUpstream chan MissionReport
	subDownstream chan MissionReport
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


func (m *Mission) RunSerially() {
	for _, subMission := range m.serial {
		subMission.Run(m)
	}
}

func (m *Mission) Run(upstream, downstream chan MissionReport) {
	if len(m.SubMissions) == 0 {
		log.Fatalf("Mission must have SubMissions")
	}

	for _, subMission := range m.SubMissions {
		switch subMission.RunType {
		case "parallel":
			m.parallel = append(m.parallel, subMission)
		default:
			m.serial = append(m.serial, subMission)
		}
	}

	for _, subMission := range m.parallel {
		go subMission.Run(m)
	}

	go m.RunSerially()

	select {
	case s := <-downstream:
		m.subMissionReports = append(m.subMissionReports, s)
	case s := <-m.upstream:
		log.Println(s)
	}
}

func (s *SubMission) Run(m *Mission) {
	s.Mission.Run(m.subUpstream, m.subDownstream)
}
