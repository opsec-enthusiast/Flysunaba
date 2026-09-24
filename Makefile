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

# install to a temporary name and rename, so a failure cannot leave a
# truncated script or manual page behind
install: ${BIN}/${PROG} ${MAN}/${PROG}.${SECTION} install-user install-doas
	@mkdir -p ${BINDIR} ${MANDIR}
	@install -m755 ${BIN}/${PROG} ${BINDIR}/.${PROG}.new \
		&& mv ${BINDIR}/.${PROG}.new ${BINDIR}/${PROG}
	@install -m444 ${MAN}/${PROG}.${SECTION} ${MANDIR}/.${PROG}.${SECTION}.new \
		&& mv ${MANDIR}/.${PROG}.${SECTION}.new ${MANDIR}/${PROG}.${SECTION}
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

# Edit a copy of /etc/doas.conf and rename it into place, so an interrupted
# make never leaves a partial rule behind: doas refuses an invalid file, which
# would lock the administrator out of doas. Rules are matched as fixed strings
# on whole lines, because a username may contain a dot. Both rules are added or
# removed only when absent or present, so the target is idempotent.
install-doas: check-fsunaba-user check-amnesic-user check-user
	@conf="/etc/doas.conf"; tmp="$$(mktemp /etc/doas.conf.XXXXXXXX)" || exit 1; \
	trap 'rm -f "$$tmp" "$$tmp.new"' EXIT; \
	if [ -f "$$conf" ]; then cp "$$conf" "$$tmp"; \
	else echo "make: creating $$conf" >&2; : > "$$tmp"; fi; \
	chown root:wheel "$$tmp" && chmod 600 "$$tmp" || exit 1; \
	doas -C "$$tmp" >/dev/null 2>&1 \
		|| { echo "make: $$conf is invalid; not modified" >&2; exit 1; }; \
	if [ -s "$$tmp" ] && [ -n "$$(tail -c 1 "$$tmp")" ]; then echo >> "$$tmp"; fi; \
	for line in "${DOAS_LINE}" "${DOAS_AMNESIC_LINE}"; do \
		if grep -Fqx "$$line" "$$tmp"; then \
			echo "make: '$$line' is already present"; \
		else \
			echo "make: adding '$$line'"; \
			echo "$$line" >> "$$tmp"; \
		fi; \
	done; \
	doas -C "$$tmp" >/dev/null 2>&1 \
		|| { echo "make: resulting $$conf is invalid; not modified" >&2; exit 1; }; \
	mv "$$tmp" "$$conf" && echo "make: updated $$conf"

install-sndio-cookie: check-fsunaba-user check-user
	@id ${FSUNABA_USER} >/dev/null 2>&1 \
		|| { echo "make: sandbox user '${FSUNABA_USER}' does not exist" >&2; exit 1; }
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
	@conf="/etc/doas.conf"; \
	if [ ! -f "$$conf" ]; then echo "make: $$conf not found"; exit 0; fi; \
	tmp="$$(mktemp /etc/doas.conf.XXXXXXXX)" || exit 1; \
	trap 'rm -f "$$tmp" "$$tmp.new"' EXIT; \
	cp "$$conf" "$$tmp"; \
	chown root:wheel "$$tmp" && chmod 600 "$$tmp" || exit 1; \
	for line in "${DOAS_LINE}" "${DOAS_AMNESIC_LINE}"; do \
		if grep -Fqx "$$line" "$$tmp"; then \
			echo "make: removing '$$line'"; \
			awk -v l="$$line" '$$0 != l' "$$tmp" > "$$tmp.new" || exit 1; \
			mv "$$tmp.new" "$$tmp"; \
		else \
			echo "make: '$$line' is not present"; \
		fi; \
	done; \
	doas -C "$$tmp" >/dev/null 2>&1 \
		|| { echo "make: resulting $$conf is invalid; not modified" >&2; exit 1; }; \
	mv "$$tmp" "$$conf" && echo "make: updated $$conf"

uninstall-sndio-cookie: check-fsunaba-user
	rm -f ~${FSUNABA_USER}/.sndio/cookie

.PHONY: build check-fsunaba-user check-amnesic-user check-user \
	install install-user install-amnesic-user install-doas \
	install-sndio-cookie uninstall uninstall-user uninstall-amnesic-user \
	uninstall-doas uninstall-sndio-cookie
