a: sleep 0.3
b: sleep 0.3
c: sleep 0.3
par [a b c]&: echo parallel-done
seq [a b c]: echo seq-done
boom: exit 9
parboom [a boom]&: echo should-not-print
