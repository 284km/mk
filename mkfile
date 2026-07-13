build: echo building
test [build]: echo testing
all [build test]: echo done-all
boom: exit 5
guarded [boom]: echo should-not-run
