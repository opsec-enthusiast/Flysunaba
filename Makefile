PREFIX ?=	/usr/local
PROG =		Fsunaba
SECTION =	1
BIN =		bin
MAN =		man
BINDIR =	${PREFIX}/${BIN}
MANDIR =	${PREFIX}/${MAN}/man${SECTION}
FSUNABA_USER ?=	fsunaba
FSUNABA_AMNESIC_USER ?=	${FSUNABA_USER}-amnesic
DOAS_LINE =	permit nopass ${USER} as ${FSUNABA_USER}
DOAS_AMNESIC_LINE =	permit nopass ${USER} as ${FSUNABA_AMNESIC_USER}

build:
	@echo "Nothing to be built."

# validate that a username is non-empty and safe to pass to shell commands
check-fsunaba-user:
	@printf '%s\n' '${FSUNABA_USER}' \
		| grep -qE '^[A-Za-z0-9][A-Za-z0-9._-]*$$' \
		|| { echo "make: invalid FSUNABA_USER '${FSUNABA_USER}'" >&2; exit 1; }

check-amnesic-user:
	@printf '%s\n' '${FSUNABA_AMNESIC_USER}' \
		| grep -qE '^[A-Za-z0-9][A-Za-z0-9._-]*$$' \
		|| { echo "make: invalid FSUNABA_AMNESIC_USER '${FSUNABA_AMNESIC_USER}'" >&2; exit 1; }

check-user:
	@printf '%s\n' '${USER}' \
		| grep -qE '^[A-Za-z0-9][A-Za-z0-9._-]*$$' \
		|| { echo "make: invalid USER '${USER}'" >&2; exit 1; }

install: ${BIN}/${PROG} ${MAN}/${PROG}.${SECTION} install-user install-doas
	mkdir -p ${BINDIR}
	install -m755 ${BIN}/${PROG} ${BINDIR}
	mkdir -p ${MANDIR}
	install -m444 ${MAN}/${PROG}.${SECTION} ${MANDIR}
	@if [ -x /usr/sbin/makewhatis ]; then \
		echo "make: updating the manual page index"; \
		/usr/sbin/makewhatis ${PREFIX}/man; \
	fi

install-user: check-fsunaba-user
	id ${FSUNABA_USER} >/dev/null 2>&1 || useradd -m ${FSUNABA_USER}
	chmod go-w ~${FSUNABA_USER}
	@if id -Gn ${FSUNABA_USER} | grep -qwE 'wheel|operator'; then \
		echo "make: warning: '${FSUNABA_USER}' is a member of a privileged group" >&2; \
	fi

# create the amnesic user whose home is erased around each session
install-amnesic-user: check-amnesic-user
	id ${FSUNABA_AMNESIC_USER} >/dev/null 2>&1 \
		|| useradd -m ${FSUNABA_AMNESIC_USER}
	chmod go-w ~${FSUNABA_AMNESIC_USER}
	@if id -Gn ${FSUNABA_AMNESIC_USER} | grep -qwE 'wheel|operator'; then \
		echo "make: warning: '${FSUNABA_AMNESIC_USER}' is a member of a privileged group" >&2; \
	fi

install-doas: check-fsunaba-user check-amnesic-user check-user
	@test -f /etc/doas.conf \
		|| { echo "make: creating /etc/doas.conf" >&2; \
		     touch /etc/doas.conf; \
		     chown root:wheel /etc/doas.conf; \
		     chmod 600 /etc/doas.conf; }
	@doas -C /etc/doas.conf >/dev/null 2>&1 \
		|| { echo "make: /etc/doas.conf is invalid; not modified" >&2; exit 1; }
	@if [ -s /etc/doas.conf ] && [ -n "$$(tail -c 1 /etc/doas.conf)" ]; then \
		echo >> /etc/doas.conf; \
	fi
	@for line in "${DOAS_LINE}" "${DOAS_AMNESIC_LINE}"; do \
		if grep -qE "^$$line$$" /etc/doas.conf; then \
			echo "make: '$$line' is already present"; \
		else \
			echo "make: adding '$$line' to /etc/doas.conf"; \
			echo "$$line" >> /etc/doas.conf; \
		fi; \
	done

install-sndio-cookie: check-fsunaba-user check-user
	@test -f ~${USER}/.sndio/cookie \
		|| { echo "make: ~${USER}/.sndio/cookie not found; play audio first" >&2; exit 1; }
	@echo "Copying sndio cookie from '${USER}' to '${FSUNABA_USER}'..."
	mkdir -p ~${FSUNABA_USER}/.sndio
	install -o ${FSUNABA_USER} -g ${FSUNABA_USER} -m 600 ~${USER}/.sndio/cookie ~${FSUNABA_USER}/.sndio/

uninstall: uninstall-doas uninstall-user uninstall-amnesic-user
	rm -f ${BINDIR}/${PROG}
	rm -f ${MANDIR}/${PROG}.${SECTION}
	@if [ -x /usr/sbin/makewhatis ]; then \
		echo "make: updating the manual page index"; \
		/usr/sbin/makewhatis ${PREFIX}/man; \
	fi

uninstall-user: check-fsunaba-user
	@id ${FSUNABA_USER} >/dev/null 2>&1 \
		&& rmuser ${FSUNABA_USER} || true

uninstall-amnesic-user: check-amnesic-user
	@id ${FSUNABA_AMNESIC_USER} >/dev/null 2>&1 \
		&& rmuser ${FSUNABA_AMNESIC_USER} || true

uninstall-doas: check-fsunaba-user check-amnesic-user check-user
	@if [ -f /etc/doas.conf ]; then \
		sed -i "/^${DOAS_LINE}$$/d" /etc/doas.conf; \
		sed -i "/^${DOAS_AMNESIC_LINE}$$/d" /etc/doas.conf; \
	fi

uninstall-sndio-cookie: check-fsunaba-user
	rm -f ~${FSUNABA_USER}/.sndio/cookie

.PHONY: build check-fsunaba-user check-amnesic-user check-user \
	install install-user install-amnesic-user install-doas \
	install-sndio-cookie uninstall uninstall-user uninstall-amnesic-user \
	uninstall-doas uninstall-sndio-cookie
