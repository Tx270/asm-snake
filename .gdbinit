set disassembly-flavor intel
set debuginfod enabled off
set pagination off
display/5uh &queue
display/5hx &queue
display/uh &queue_head
display/uh &queue_count
display/u $rax

break print_spaces
run