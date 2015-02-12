PRIVDIR := ../priv

LD ?= ld
CC ?= gcc
RM ?= rm

CFLAGS ?= -O2

override CFLAGS += -std=gnu99 -Wall -fpic
override LDFLAGS += -shared -fpic

all : $(PRIVDIR)/dhcp_server.so

$(PRIVDIR)/dhcp_server.so : dhcp_server.o
	$(CC) $(LDFLAGS) -o $@ $^

clean:
	$(RM) -f $(PRIVDIR)/dhcp_server.so dhcp_server.o

