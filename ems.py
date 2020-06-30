import tkinter as tk
from tkinter import *

ssh_stuff = []
def CurSelet(event):
    widget = event.widget
    selection=widget.curselection()
    picked = widget.get(selection[0])
    print(picked)
def show_entry_fields():
    print("Username: %s\nNumber of vm(s): %s\nName of pc:%sd" % (username.get(), vm.get(), pc.get))
def vm_select(username,vm,pc,num_vm):
    vm_arr = list()   
    print("we here")
    print(vm)   
    if(vm == 'meb'):
        if(int(num_vm) > 0):
            for x in range(0,int(num_vm)):
                print("insidefor")
                i = x+1
                vm_arr.append(username+"@pc02"+"-mebvm-"+i+"emulab.net")
                print (vm_arr[x])

master = tk.Tk()
tk.Label(master, 
         text="POWDER Username").grid(row=0)
tk.Label(master, 
         text= "Number of vm(s) to be used").grid(row=1)
tk.Label(master, 
         text= "Name of PC").grid(row=2)
tk.Label(master,text = "Choose the nodes being used for the experiment").grid(row = 3, column = 0)
listbox = tk.Listbox(master)
listbox.bind('<<ListboxSelect>>',CurSelet)
listbox.grid(row=4)

for item in ["fortvm", "bookstore", "meb", "etc"]:
    listbox.insert(END, item)

username = tk.Entry(master)
vm = tk.Entry(master)
pc = tk.Entry(master)

username.grid(row=0, column=1)
vm.grid(row=1, column=1)
pc.grid(row=2, column=1)

tk.Button(master, 
          text='Quit', 
          command=master.quit).grid(row=5, 
                                    column=0, 
                                    sticky=tk.W, 
                                    pady=4)
tk.Button(master, 
          text='Show', command=show_entry_fields).grid(row=5, 
                                                       column=1, 
                                                       sticky=tk.W, 
                                                       pady=4)
vm_name = listbox.get(ANCHOR)
ssh1 = tk.Button(master, text = 'perform ssh', command = lambda: vm_select(username, vm_name,pc,vm))
ssh1.grid(row=5, 
        column=2, 
        sticky=tk.W, 
        pady=4)
tk.mainloop()