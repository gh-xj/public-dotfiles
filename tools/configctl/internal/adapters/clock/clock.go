package clock

import "time"

type Clock interface {
	Now() time.Time
}

type System struct{}

func (System) Now() time.Time {
	return time.Now()
}

type Fixed struct {
	Time time.Time
}

func (c Fixed) Now() time.Time {
	return c.Time
}
