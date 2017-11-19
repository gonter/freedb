/*
 *   cddbd - CD Database Protocol Server
 *
 *   Copyright (C) 1996-1997  Steve Scherf (steve@moonsoft.com)
 *   Portions Copyright (C) 1999-2006  by various authors
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation; either version 2 of the License, or
 *   (at your option) any later version.
 *
 *   This program is distributed in the hope that it will be useful,
 *   but WITHOUT ANY WARRANTY; without even the implied warranty of
 *   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *   GNU General Public License for more details.
 *
 *   You should have received a copy of the GNU General Public License
 *   along with this program; if not, write to the Free Software
 *   Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 *
 */

#ifndef LINT
static char *const _mail_c_ident_ = "@(#)$Id: mail.c,v 1.32 2006/04/16 16:26:33 megari Exp $";
#endif

#include <sys/wait.h>
#include <unistd.h>

#include <ctype.h>
#include <errno.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include "cddbd.h"


/* Preprocessor definitions. */
#define SCAN_ADDR	0
#define SCAN_NAME	1
#define SCAN_MISC	2

/* Prototypes. */
int cddbd_submit(FILE *, email_hdr_t *, int, char *);
int add_hdr(char *dir, unsigned int discid, email_hdr_t *eh, char *errstr);
int cddbd_email_cmd(FILE *, email_hdr_t *, int, char *);
int get_charset(char *, email_hdr_t *, char *);
int get_encoding(char *, email_hdr_t *, char *);
int parse_header(FILE *, email_hdr_t *, char *);
/*int return_mail(FILE *, email_hdr_t *, int, char *);*/
int scan_from(char *, char *, int);
void cpy_sender(char *, char *, char *, char *);
static FILE *get_body(FILE *, email_hdr_t *, char *, char *);
static FILE *build_returnmail(FILE *fp, FILE *tfp, char *tmail, char *errstr);
#ifdef DB_WINDOWS_FORMAT
int mergeUnix2WinDB(char *, char *, int);
#endif

/* Static variables. */
static char *x_cddbd_note = "X-Cddbd-Note";
static char *note = "Note: %s\n\n";
static char *sub_rej_subj = "Rejected freedb submission";
static char *sub_send_subj = "cddb %255s %08x";
static char *test_rej_subj = "Rejected freedb test submission";
static char *test_ok_subj = "Successful freedb test submission";
static char *cmd_send_subj = "cddb #command %16s";
static char *cmd_ok_subj = "cddb #response ok %s";
static char *cmd_rej_subj = "cddb #response failed %s";
/* static char *gen_rej_subj = "Rejected freedb email"; */
static char *gen_incl = "> %s\n";
static char *gen_incl_blank = ">\n";
static char *null_incl = "%s\n";
static char *null_incl_blank = "\n";

static char *test_ok_body[] = {
	"Your freedb test submission was accepted.\n",
	"\n",
	"The test submission follows:\n",
	0
};

static char *test_ok_sig[] = {
	"\n",
	"Response generated by the CDDB daemon.\n",
	"\n",
	0
};

static char *sub_rej_body[] = {
	"Your freedb submission was rejected for the following reason:\n",
	"\n",
	"%s\n",
	"\n",
	"Please fix the problem before you resubmit it. Only the first\n",
	"error in your submission was noted - there may be others. If you\n",
	"continue to have trouble, it may be due to a bug in your CD\n"
	"player software. If you suspect this, try acquiring a newer version.",
	"\n\n",
	"The rejected submission follows:\n",
	0
};

static char *gen_rej_body[] = {
	"Your mail to the CDDB daemon failed for the following reason:\n",
	"\n",
	"%s\n",
	"\n",
	"Please fix the problem before you resend it. If you continue to\n",
	"have trouble, it may be due to a bug in the software used to\n",
	"send the mail.",
	"\n\n",
	"The rejected mail follows:\n",
	0
};

static char *gen_rej_sig[] = {
	"\n",
	"If you need assistance, please take a look at the FAQ\n",
	"at http://www.freedb.org/modules.php?name=Sections&sop=viewarticle&artid=26\n",
	"If the FAQ doesn't help, send an e-mail to: %s\n",
	"\n",
	"Response generated by the CDDB daemon.\n",
	"\n",
	0
};

static char *start_type[] = {
	"<",
	"(\"",
	""                 /* huh? shouldn't that be <(\" ?? [+gg] */
};

static char *end_type[] = {
	">",
	")\"",
	"<(\""
};

/* truly global variables. mainly used in inet.c */
/* Header names */
char *content_encoding = "Content-Transfer-Encoding";
char *content_type = "Content-Type";
char *expires = "Expires";
char *rpath = "Return-Path";
char *content_len = "Content-Length";
char *mime_ver = "Mime-Version";
char *from = "From";
char *x_cddbd_from = "X-Cddbd-From";
char *x_cddbd_echo = "X-Cddbd-Echo";
char *x_cddbd_crc = "X-Cddbd-CRC";
char *to = "To";
char *subj = "Subject";
char *x_sender = "X-Sender";

/* text constants used in headers */
char *text_plain = "text/plain";
char *multi_alt = "multipart/alternative";
char *boundary = "boundary";
char *charset = "charset";

charset_t charsets[] = {
	{ "us-ascii", 0 },
	{ "iso-8859-1", DF_ENC_LATIN1 },
	{ "utf-8", DF_ENC_UTF8 },
	{ 0, 0 }
};


void
cddbd_mail(int flags)
{
	int ret;
	FILE *fp;
	FILE *tfp= (FILE *) 0;
	FILE *tfp2= (FILE *) 0;
	email_hdr_t eh;
	char *tmail;
	char *tmail2;
	char *tmail3;
	char buf[CDDBBUFSIZ];
	char errstr[CDDBBUFSIZ];

	errstr[0] = '\0';

	/* Create a temporary file for the mail. */
	tmail = cddbd_mktemp();

	if((fp = fopen(tmail, "w+")) == NULL) {
		cddbd_snprintf(buf, sizeof(buf),
		    "Can't open mail tmp file %s (%d)", tmail, errno);

		cddbd_log(LOG_ERR | LOG_MAIL, "%s", buf);

		/* Print to stderr so the bounced mail gets it. */
		fprintf(stderr, "%s\n", buf);

		quit(QUIT_ERR);
	}

	/* Put the mail into the temp file. */
	while(fgets(buf, sizeof(buf), stdin) != NULL) {
		if(fputs(buf, fp) == EOF) {
			cddbd_snprintf(buf, sizeof(buf),
			    "Can't write mail tmp file %s (%d)", tmail, errno);

			cddbd_log(LOG_ERR | LOG_MAIL, "%s", buf);

			/* Print to stderr so the bounced mail gets it. */
			fprintf(stderr, "%s\n", buf);

			quit(QUIT_ERR);
		}
	}

	/* Put the pointer back to the start of the file for reading. */
	rewind(fp);

	/* parse the header, fill in "eh" structure */
	ret = parse_header(fp, &eh, errstr);

	tmail2 = cddbd_mktemp();

	if(ret == EE_OK && (tfp = get_body(fp, &eh, tmail2, errstr)) == NULL)
		ret = EE_ERROR;
	
	/* Put the pointer back to the start of the file for reading. */
	rewind(fp);
	
	tmail3 = cddbd_mktemp();
	
	if(ret == EE_OK && (tfp2=build_returnmail(fp, tfp, tmail3, errstr)) == NULL)
		ret = EE_ERROR;
		
	if(ret == EE_OK) {
		switch(eh.eh_class) {
		case EC_SUBMIT:
			ret = cddbd_submit(tfp, &eh, flags, errstr);

			/* Give back happy mail. */
			if(ret == EE_OK && (flags & MF_TEST)) {
				ret = return_mail(tfp2, &eh, flags, errstr);

				if(ret != EE_OK) {
					cddbd_log(LOG_ERR | LOG_MAIL,
						"Couldn't send test response.");
				}
			}

			break;

		case EC_COMMAND:
			ret = cddbd_email_cmd(tfp, &eh, flags, errstr);
			break;

		case EC_NONE:
		default:
			ret = EE_ERROR;
			break;
		}
	}

	if(ret != EE_OK) {
		if(eh.eh_flags & EH_RCPT) {
			/* We have a sender, give him mail directly. */
			if (tfp2 != NULL)
				ret = return_mail(tfp2, &eh, (flags | MF_FAIL), errstr);
			else
				ret = return_mail(fp, &eh, (flags | MF_FAIL), errstr);
		}

		if(ret != EE_OK) {
			/* We have no sender, give him mail indirectly. */
			cddbd_snprintf(buf, sizeof(buf),
			    "Unable to process email: %s", errstr);

			cddbd_log(LOG_ERR | LOG_MAIL, "%s", buf);

			/* Print to stderr so the bounced mail gets it. */
			fprintf(stderr, "%s\n", buf);
		}
	}

	fclose(fp);
	if (tfp != (FILE *) 0) fclose(tfp);
	if (tfp2 != (FILE *) 0) fclose(tfp2);

	cddbd_freetemp(tmail);
	cddbd_freetemp(tmail2);
	cddbd_freetemp(tmail3);

	if(ret == EE_OK)
		quit(QUIT_OK);
	else
		quit(QUIT_ERR);
}


int
cddbd_submit(FILE *fp, email_hdr_t *eh, int flags, char *errstr)
{
	int i;
	int len;
	int ret;
	int dbflags;
	db_t *db;
	char buf[CDDBBUFSIZ];
	char buf2[CDDBBUFSIZ];
	struct stat sbuf;

	/* Set the interface type. */
	interface = IF_SUBMIT;

	if(!(flags & MF_TEST))
		hperm = *ck_host_perms(interface);

	if((ret = validate_email(fp, eh, errstr)) != EE_OK)
		return ret;

	if(!WRITE_OK(hperm) && !(flags & MF_TEST)) {
		cddbd_snprintf(errstr, CDDBBUFSIZ,
		    "Email submissions disallowed");

		return EE_ERROR;
	}

	if(categ_index(eh->eh_category) < 0) {
		cddbd_snprintf(errstr, CDDBBUFSIZ, "Invalid DB category: %s\n"
		    "Valid categories are:", eh->eh_category);

		for(i = 0, len = strlen(errstr); categlist[i] != 0; i++) {
			cddbd_snprintf(&errstr[len], (CDDBBUFSIZ - len),
			    " %s", categlist[i]);
			len += strlen(categlist[i]) + 1;
		}

		return EE_ERROR;
	}

	/* Specify acceptable charsets. */
	dbflags = charsets[eh->eh_charset].df_flags;
	if((dbflags & DF_ENC_LATIN1) && utf_as_iso == UAI_CONVERT)
		dbflags |= DF_ENC_UTF8;

	if(!(flags & MF_TEST))
		dbflags |= DF_CK_SUBMIT;

	rewind(fp);

	db = db_read(fp, buf, (DF_MAIL | DF_SUBMITTER | dbflags));
	if(db == 0) {
		cddbd_snprintf(errstr, CDDBBUFSIZ, "Invalid DB submission: %s",
		    buf);

		return EE_ERROR;
	}

	/* Check and disambiguate charset. */
	if (db_disam_charset(db)) {
		cddbd_snprintf(errstr, CDDBBUFSIZ,
			"Entry rejected: looks like UTF-8.");
		return EE_ERROR;
	}

	if(!(flags & MF_TEST)) {
		/* Check for postdir, and create if it doesn't exist. */
		if(stat(postdir, &sbuf)) {
			if(mkdir(postdir, (mode_t)db_dir_mode)) {
				cddbd_log(LOG_ERR,
				    "Failed to create post dir %s.", postdir);

				cddbd_snprintf(errstr, CDDBBUFSIZ,
					"Internal server file error");

				return EE_ERROR;
			}

			(void)cddbd_fix_file(postdir, db_dir_mode, db_uid, db_gid);
		}
		else if(!S_ISDIR(sbuf.st_mode)) {
			cddbd_log(LOG_ERR, "%s is not a directory.", postdir);

			cddbd_snprintf(errstr, CDDBBUFSIZ,
			    "Internal server file error");

			return EE_ERROR;
		}

		cddbd_snprintf(buf2, sizeof(buf), "%s/%s",
					   postdir, eh->eh_category);

		/* zeke - add eh info to db struct for writing to post entry */
		db->db_eh.eh_flags = eh->eh_flags;
		db->db_eh.eh_charset = eh->eh_charset;
		db->db_eh.eh_encoding = eh->eh_encoding;
		strcpy (db->db_eh.eh_to, eh->eh_to);
		strcpy (db->db_eh.eh_rcpt, eh->eh_rcpt);
		strcpy (db->db_eh.eh_host, eh->eh_host);
		/* end zeke */

		if(!db_post(db, buf2, eh->eh_discid, buf)) {
			if(db_errno != DE_INVALID) {
				cddbd_snprintf(errstr, CDDBBUFSIZ,
				    "Internal DB server error: %s", buf);
			}
			else
				cddbd_snprintf(errstr, CDDBBUFSIZ,
				    "Invalid DB file: %s", buf);

			return EE_ERROR;
		}

		cddbd_log(LOG_INFO | LOG_WRITE,
		    "Write (via SMTP - %s): %s %08x", eh->eh_to,
		    eh->eh_category, eh->eh_discid);
	}
	else {
		cddbd_log(LOG_INFO, "Test email submission (from %s): %s %08x",
		    eh->eh_to, eh->eh_category, eh->eh_discid);
	}

	return EE_OK;
}


int
cddbd_email_cmd(FILE *fp, email_hdr_t *eh, int flags, char *errstr)
{
	int ret;
	int found;
	pid_t f;
	char *tcmd;
	char buf[CDDBCMDLEN];
	struct stat sbuf;

	/* Set the interface type. */
	interface = IF_EMAIL;

	hperm = *ck_host_perms(interface);

	if(flags & MF_TEST) {
		cddbd_snprintf(errstr, CDDBBUFSIZ,
		    "Email commands not accepted at this address");

		return EE_ERROR;
	}

	if((ret = validate_email(fp, eh, errstr)) != EE_OK)
		return ret;

	found = 0;
	rewind(fp);

	while(fgets(buf, sizeof(buf), fp))
		if(!strncmp(buf, asy_prefix[0], strlen(asy_prefix[0]))) {
			found++;
			break;
		}

	if(!found) {
		cddbd_snprintf(errstr, CDDBBUFSIZ,
		    "No CDDBP command found in mail body");

		return EE_ERROR;
	}

	/* Create a temporary file for the mail. */
	tcmd = cddbd_mktemp();

	if((fp = fopen(tcmd, "w+")) == NULL) {
		cddbd_snprintf(errstr, CDDBBUFSIZ,
		    "Internal server error: can't open temp file %s", tcmd);

		return EE_ERROR;
	}

	f = cddbd_fork();

	/* We're the child. Do the command. */
	if(f == 0) {
		dup2(fileno(fp), 1);
		dup2(fileno(fp), 2);
		fclose(fp);
		close(0);

		_quit(cddbd_async_command(buf, 0), 0);
	}

	if(f < 0) {
		cddbd_snprintf(errstr, CDDBBUFSIZ,
		    "Internal server error: can't fork");

		fclose(fp);
		cddbd_freetemp(tcmd);

		return EE_ERROR;
	}

	if(wait(0) == -1 && errno != ECHILD) {
		cddbd_snprintf(errstr, CDDBBUFSIZ,
		    "Internal server error: failed to wait on child (%d)",
		    errno);

		fclose(fp);
		cddbd_freetemp(tcmd);

		return EE_ERROR;
	}

	if(stat(tcmd, &sbuf)) {
		cddbd_snprintf(errstr, CDDBBUFSIZ,
		    "Internal server error: can't stat output file %s (%d)",
		    tcmd, errno);

		fclose(fp);
		cddbd_freetemp(tcmd);

		return EE_ERROR;
	}

	/* Put something in the file if it's empty. */
	if(sbuf.st_size == 0) {
		fprintf(fp, "403 Server error.\n");
		fflush(fp);
	}

	ret = return_mail(fp, eh, (flags | MF_ENC), errstr);
	if(ret != EE_OK) {
		cddbd_snprintf(errstr, CDDBBUFSIZ,
		    "Internal server error: can't generate response mail");
	}

	fclose(fp);
	cddbd_freetemp(tcmd);

	/* Reset the interface type so we don't log a second hello. */
	interface = IF_SUBMIT;

	return ret;
}


int
validate_email(FILE *fp, email_hdr_t *eh, char *errstr)
{
	uint32_t crc;
	uint32_t mcrc;
	ct_key_t *key;

	if(eh->eh_flags & EH_CRC) {
		if(PASSWD_REQ(hperm)) {
			if((key = getpasswd(hperm.hp_pwdlbl)) == NULL) {
				cddbd_snprintf(errstr, CDDBBUFSIZ,
				    "Validation string lookup failed");

				return EE_ERROR;
			}
		}
		else
			key = 0;

		if(crc_email(&crc, fp, eh->eh_rcpt, eh->eh_subj, errstr) !=
		    EE_OK)
			return EE_ERROR;

		mcrc = strtocrc(eh->eh_crc, 0, key);

#if 1
		if(crc != mcrc) {
#else
		if(key && crc != mcrc) {
#endif
#if 1
			cddbd_snprintf(errstr, CDDBBUFSIZ,
			    "CRC in email (%08X) differs from expected CRC "
			    "(%08X)", mcrc, crc);

			return EE_ERROR;
#else
			cddbd_log(LOG_ERR | LOG_PASSWD,
			    "CRC in email (%08X) differs from expected CRC "
			    "(%08X)", mcrc, crc);
#endif
		}

		hperm.hp_passwd = HP_PASSWD_OK;

		return EE_OK;
	}
	else if(hperm.hp_passwd == HP_PASSWD_REQ) {
		cddbd_snprintf(errstr, CDDBBUFSIZ,
		    "Required CRC missing from email header");

		return EE_ERROR;
	}

	return EE_OK;
}


int
crc_email(uint32_t *crc, FILE *fp, char *rcpt, char *subj, char *errstr)
{
	uint32_t len;
	uint32_t tcrc[3];

	rewind(fp);

	if(crc32(CRC_FILE, fp, &tcrc[0], &len) == -1 ||
	    crc32(CRC_STRING, rcpt, &tcrc[1], &len) == -1 ||
	    crc32(CRC_STRING, subj, &tcrc[2], &len) == -1) {
		cddbd_snprintf(errstr, CDDBBUFSIZ,
		    "Can't calculate email CRC (%d)", errno);

		return EE_ERROR;
	}

	*crc = tcrc[0] ^ tcrc[1] ^ tcrc[2];

	return EE_OK;
}


static FILE *
get_body(FILE *fp, email_hdr_t *eh, char *tmail, char *errstr)
{
	int len;
	int found;
	FILE *tfp;
	char *p;
	char buf[CDDBBUFSIZ];
	int (*efunc)();

	if((tfp = fopen(tmail, "w+")) == NULL) {
		cddbd_snprintf(errstr, CDDBBUFSIZ,
		    "Can't open mail tmp file %s (%d)", tmail, errno);

		return NULL;
	}

	efunc = encoding_types[eh->eh_encoding].en_decode;
	if(efunc != 0 && (efunc)(EO_START, 0, 0, 0) != EN_OK) {
		cddbd_snprintf(errstr, CDDBBUFSIZ,
		    "Failed to initiate email decoding.");

		return NULL;
	}

	found = 0;

	/* Put the mail into the temp file. */
	while(fgets(buf, sizeof(buf), fp) != NULL) {
		if((eh->eh_flags & EH_BOUNDARY) &&
		    strstr(buf, eh->eh_boundary) != NULL) {
			found++;
			break;
		}

		len = strlen(buf);

		if(efunc != 0) {
			if((efunc)(EO_DECODE, buf, &p, &len) != EN_OK) {
				cddbd_snprintf(errstr, CDDBBUFSIZ,
				    "Failed to perform email decoding.");

				return NULL;
			}
		}
		else
			p = buf;

		if(len != 0 && fwrite(p, 1, len, tfp) != len) {
			cddbd_snprintf(errstr, CDDBBUFSIZ,
			    "Can't write mail tmp file %s (%d)",
			    tmail, errno);

			return NULL;
		}
	}

	if(efunc != 0 && (efunc)(EO_END, 0, 0, 0) != EN_OK) {
		cddbd_snprintf(errstr, CDDBBUFSIZ,
		    "Failed to terminate email decoding.");

		return NULL;
	}

	if((eh->eh_flags & EH_BOUNDARY) && !found) {
		cddbd_snprintf(errstr, CDDBBUFSIZ,
		    "End boundary not found in mail.");

		return NULL;
	}

	fflush(tfp);
	rewind(tfp);

	return tfp;
}


/* Read a header field, unfolding multiple lines if necessary.
 * Arguments and return value are just like fgets().
 */
static char *get_hdr_line(char *buf, int size, FILE *fp)
{
	int c, i = 0;

	while((c = fgetc(fp)) != EOF) {
		if(c == '\n') {
			c = fgetc(fp);
			if(c == ' ' || c == '\t') {
				if(i > 0 && buf[i - 1] == '\r')
					--i;
			}
			else {
			  if(c != EOF)
			  	ungetc(c, fp);
			  if(i + 1 < size)
			  	buf[i++] = '\n';
			  break;
			}
		}
		if(i + 1 < size)
			buf[i++] = c;
	}
	if(size)
		buf[i] = '\0';
	return i ? buf : 0;
}

/* builds the info from the submission to be returned in a rejection notice */
/* or test submission response by taking the original mail header and the   */
/* decoded mail                                                             */

static FILE *build_returnmail(FILE *fp, FILE *tfp, char *tmail, char *errstr)
{
	int len;
	int blank;
	char buf[CDDBBUFSIZ];
	char *p;
	FILE *tfp2;
	
	if((tfp2 = fopen(tmail, "w+")) == NULL) {
		cddbd_snprintf(errstr, CDDBBUFSIZ,
		    "Can't open mail tmp file %s (%d)", tmail, errno);
		return NULL;
	}
	
	while(fgets(buf, sizeof(buf), fp) != NULL) {
		blank = (buf[0] == '\n' ||
			 (buf[0] == '\r' && buf[1] == '\n'));
		len = strlen(buf);
		p = buf;
		if(len != 0 && fwrite(p, 1, len, tfp2) != len) {
			cddbd_snprintf(errstr, CDDBBUFSIZ,
			    "Can't write mail tmp file %s (%d)",
			    tmail, errno);
			return NULL;
		}
		if (blank) break;
	}
	while(fgets(buf, sizeof(buf), tfp) != NULL) {
				len = strlen(buf);
		p = buf;
		if(len != 0 && fwrite(p, 1, len, tfp2) != len) {
			cddbd_snprintf(errstr, CDDBBUFSIZ,
			    "Can't write mail tmp file %s (%d)",
			    tmail, errno);
			return NULL;
		}
	}
		
	fflush(tfp2);
	rewind(tfp2);
	rewind(tfp);
	
	return tfp2;
}		

			 
/* This function parses the header of an email that
 * can be read from an open file handle.
 * Note, T2D: There are a few short cuts that should be fixed.
 */
int
parse_header(FILE *fp, email_hdr_t *eh, char *errstr)
{
	int len;
	int blank;

  /* various flags to indicate what header parts were already seen */
	int header= 0;
	int gotsubj= 0;
	int gotenc= 0;
	int gotset= 0;
	int waitbound= 0;

	char *p;
	char *s;
	char buf[CDDBBUFSIZ];
	char buf2[CDDBBUFSIZ];
	char set[CDDBBUFSIZ];
	char enc[CDDBBUFSIZ];

	eh->eh_flags = 0;
	eh->eh_class = EC_NONE;
	eh->eh_charset = CC_US_ASCII;
	eh->eh_encoding = CE_7BIT;

	while(get_hdr_line(buf, sizeof(buf), fp)) {
		strcpy(buf2, buf); /* pointless copy */
		blank = (buf[0] == '\n' ||
			 (buf[0] == '\r' && buf[1] == '\n'));

		if(!strncmp(buf, from, strlen(from)) ||
		    !strncmp(buf, x_cddbd_from, strlen(rpath)) ||
		    (!header && !strncmp(buf, rpath, strlen(rpath)))) {
			p = buf;
			while(*p != '\0' && !isspace(*p))
				p++;
			while(*p != '\0' && isspace(*p))
				p++;

			if(*p != '\0') {
				cpy_sender(p, eh->eh_rcpt, eh->eh_to,
				    eh->eh_host);

				eh->eh_flags |= EH_RCPT;
				header++;
			}

			continue;
		}

		if(!header)
			continue;

		if(!strncmp(buf, subj, strlen(subj))) {
			p = buf;
			while(*p != '\0' && !isspace(*p))
				p++;
			while(*p != '\0' && isspace(*p))
				p++;

			if(sscanf(p, cmd_send_subj, eh->eh_serial))
				eh->eh_class = EC_COMMAND;
			else if(sscanf(p, sub_send_subj, eh->eh_category,
			    &eh->eh_discid) == 2)
				eh->eh_class = EC_SUBMIT;
			else {
				strcpy(errstr, "Malformed subject in header");
				return EE_ERROR;
			}

			strip_crlf(p);
			strncpy(eh->eh_subj, p, sizeof(eh->eh_subj));
			eh->eh_subj[sizeof(eh->eh_subj) - 1] = '\0';

			gotsubj++;
			eh->eh_flags |= EH_SUBJECT;
		}
		else if(!cddbd_strncasecmp(buf, x_cddbd_crc,
		    strlen(x_cddbd_crc))) {
			/* Skip junk. */
			p = buf + strlen(x_cddbd_crc) + 1;
			while(*p != '\0' && !isxdigit(*p))
				p++;

			/* Find the crc. */
			if(sscanf(p, "%255[a-zA-Z0-9]", buf2) != 1 ||
			    strlen(buf2) != CDDBXCRCLEN) {
				cddbd_snprintf(errstr, CDDBBUFSIZ,
				    "Malformed %s in header", x_cddbd_crc);

				return EE_ERROR;
			}

			strcpy(eh->eh_crc, buf2);
			eh->eh_flags |= EH_CRC;
		}
		else if(!cddbd_strncasecmp(buf, x_cddbd_echo,
		    strlen(x_cddbd_echo))) {
			/* Skip junk. */
			p = buf + strlen(x_cddbd_echo) + 1;
			while(*p != '\0' && isspace(*p))
				p++;

			/* Find the echo string. */
			if(sscanf(p, "%255[^\n\r]", buf2) != 1 ||
			    strlen(buf2) > CDDBXECHOLEN) {
				cddbd_snprintf(errstr, CDDBBUFSIZ,
				    "Invalid %s in header", x_cddbd_echo);

				return EE_ERROR;
			}

			strcpy(eh->eh_echo, buf2);
			eh->eh_flags |= EH_ECHO;
		}
		else if(!cddbd_strncasecmp(buf, x_cddbd_note,
		    strlen(x_cddbd_note))) {
			/* Skip junk. */
			p = buf + strlen(x_cddbd_note) + 1;
			while(*p != '\0' && isspace(*p))
				p++;

			/* Find the note string. */
			if(sscanf(p, "%255[^\n\r]", buf2) != 1 ||
			    strlen(buf2) > CDDBXNOTELEN) {
				cddbd_snprintf(errstr, CDDBBUFSIZ,
				    "Invalid %s in header", x_cddbd_note);

				return EE_ERROR;
			}

			strcpy(eh->eh_note, buf2);
			eh->eh_flags |= EH_NOTE;
		}
		else if(!cddbd_strncasecmp(buf, content_type,
		    strlen(content_type))) {
			if((p = cddbd_strcasestr(buf, charset)) != 0) {
				/* Skip junk. */
				p += strlen(charset);
				while(*p != '\0' && !isalpha(*p) &&
				    !isdigit(*p))
					p++;

				/* Find the charset. */
				if(sscanf(p, "%255[a-zA-Z0-9_-]", set) != 1) {
					cddbd_snprintf(errstr, CDDBBUFSIZ,
					    "Malformed %s in header",
					    content_type);
					return EE_ERROR;
				}

				gotset++;
			}

			if((p = cddbd_strcasestr(buf, boundary)) != 0) {
				/* Skip junk. */
				p += strlen(boundary);
				while(*p != '\0') {
					if(*p == '=') {
						p++;
						break;
					}
					p++;
				}

				if(*p ==  '"') {
					p++;
					s = "%255[^\"]";
				}
				else
					s = "%255s";

				/* Find the boundary string. */
				if(sscanf(p, s, eh->eh_boundary) != 1) {
					cddbd_snprintf(errstr, CDDBBUFSIZ,
					    "Malformed %s in header",
					    content_type);
					return EE_ERROR;
				}

				len = strlen(eh->eh_boundary);
				if(eh->eh_boundary[len - 1] == '"' ||
				    eh->eh_boundary[len - 1] == ';')
					eh->eh_boundary[len - 1] = '\0';

				eh->eh_flags |= EH_BOUNDARY;

				waitbound++;
			}
		}
		else if(!cddbd_strncasecmp(buf, content_encoding,
		    strlen(content_encoding))) {
			/* Skip junk. */
			p = buf + strlen(content_encoding);
			while(*p != '\0' && !isalpha(*p) && !isdigit(*p))
				p++;

			/* Find the encoding. */
			if(sscanf(p, "%[a-zA-Z0-9_-]", enc) != 1) {
				cddbd_snprintf(errstr, CDDBBUFSIZ,
				    "Malformed %s in header", content_encoding);

				return EE_ERROR;
			}

			gotenc++;
		}
		else if(waitbound && strstr(buf, eh->eh_boundary) != NULL) {
			waitbound = 0;
		}
		else if(blank && !waitbound) {
			get_rmt_hostname(-1, eh->eh_host, rhost);

			if(!gotsubj) {
				strcpy(errstr, "Missing subject in header");
				return EE_ERROR;
			}

			if(gotenc && !get_encoding(enc, eh, errstr))
				return EE_ERROR;

			if(gotset && !get_charset(set, eh, errstr))
				return EE_ERROR;

			return EE_OK;
		}
	}

	if(waitbound)
		strcpy(errstr, "Missing boundary string");
	else
		strcpy(errstr, "Malformed email header");

	return EE_ERROR;
}


int
get_encoding(char *encoding, email_hdr_t *eh, char *errstr)
{
	int i;

	/* Look for the encoding in the supported list. */
	for(i = 0; encoding_types[i].en_type != 0; i++)
		if(!cddbd_strcasecmp(encoding, encoding_types[i].en_type))
			break;

	/* Unknown encoding. */
	if(encoding_types[i].en_type == 0) {
		cddbd_snprintf(errstr, CDDBBUFSIZ,
		    "Unsupported %s in header: %s", content_encoding,
		    encoding);

		return 0;
	}

	eh->eh_encoding = i;
	return 1;
}


int
get_charset(char *set, email_hdr_t *eh, char *errstr)
{
	int i;

	/* Look for the charset in the supported list. */
	for(i = 0; charsets[i].name != 0; i++)
		if(!cddbd_charcasecmp(set, charsets[i].name))
			break;

	/* Unknown charset. */
	if(charsets[i].name == 0) {
		cddbd_snprintf(errstr, CDDBBUFSIZ,
		    "Unsupported %s in header: %s", charset, set);

		return 0;
	}

	eh->eh_charset = i;
	return 1;
}

void
cpy_sender(char *str, char *rcpt, char *to, char *fhost)
{
	int gotaddr= 0;
	int gotname= 0;
	int gotmisc= 0;
	char *p;
	char *pa= "unknown";	/* see NOTE below */
	char *pn= "unknown"; 	/* see NOTE below */
	char addr[CDDBBUFSIZ];
	char name[CDDBBUFSIZ];
	char misc[CDDBBUFSIZ];

	/* Scan the string for the name and address. */
	if(scan_from(str, addr, SCAN_ADDR))
		gotaddr = 1;

	if(scan_from(str, name, SCAN_NAME))
		gotname = 1;

	if((!gotaddr || !gotname) && scan_from(str, misc, SCAN_MISC))
		gotmisc = 1;

	/* NOTE: there might be cases where neither SCAN_ADDR nor SCAN_NAME
	 * nor SCAN_MISC return plausible values.  Therefore pa and pn need
	 * to be initialized to avoid picking-up garbage.  Maybe it would
	 * make sense not to process such cases at all.
	 */

	if(gotaddr) {
		pa = addr;
	}
	else if(gotmisc) {
		pa = misc;
		gotaddr = 1;
		gotmisc = 0;
	}

	if(gotname) {
		pn = name;
	}
	else if(gotmisc) {
		pn = misc;
		gotname = 1;
	}

	/* We couldn't parse the string, use the raw "from". */
	if(!gotaddr) {
		strcpy(rcpt, str);

		pn = &rcpt[strlen(rcpt) - 1];
		if(*pn == '\n')
			*pn = '\0';

		strcpy(to, rcpt);
		strcpy(fhost, "unknown");

		return;
	}

	/* Copy the relevant parts. */
	cddbd_snprintf(rcpt, CDDBBUFSIZ, "%s", pa);

	if(gotname)
		cddbd_snprintf(to, CDDBBUFSIZ, "%s (%s)", pa, pn);
	else
		cddbd_snprintf(to, CDDBBUFSIZ, "%s", pa);

	/*
	 * Get the hostname from the address. If it's a complicated
	 * address, this may goof up. If there's no discernible host we 
	 * must assume it's because there isn't one, so call it "localhost".
	 */
	if((p = strrchr(pa, '@')) != NULL)
		cddbd_snprintf(fhost, CDDBBUFSIZ, "%s", (p + 1));
	else if((p = strchr(pa, '!')) != NULL) {
		*p = '\0';
		cddbd_snprintf(fhost, CDDBBUFSIZ, "%s", pa);
	}
	else if((p = strrchr(pa, '%')) != NULL)
		cddbd_snprintf(fhost, CDDBBUFSIZ, "%s", (p + 1));
	else
		strcpy(fhost, LHOST);
}


int
scan_from(char *str, char *buf, int type)
{
	char *p;
	char *p1;

	/* Skip leading white space. */
	p = str;
	while(*p != '\0' && isspace(*p))
		p++;

	/* Scan for a beginning marker. */
	while(*p != '\0' && !is_instr(*p, start_type[type]))
		p++;

	if(*p == '\0')
		return 0;

	/* Strip off marker, if there is one. */
	if(*start_type[type] != '\0')
		p++;

	p1 = buf;

	/* Copy in relevant portion of the string. */
	while(*p != '\0' && !is_instr(*p, end_type[type])) {
		*p1 = *p;
		p++;
		p1++;
	}

	/* Strip off trailing white space. */
	p1--;
	while(isspace(*p1))
		p1--;
	p1++;
	*p1 = '\0';
	
	return 1;
}


int
return_mail(FILE *fp, email_hdr_t *eh, int flags, char *errstr)
{
	int i;
	int len;
	FILE *nfp;
	char *p;
	char *incl;
	char *bincl;
	char *subj;
	char **sig;
	char **body;
	char *copy_addr;
	char *rtn_addr;
	char *tret;
	char *echo;
	char buf[CDDBBUFSIZ];
	char subj_buf[CDDBBUFSIZ];
	struct stat sbuf;
	int charset = -1;

	/* Create a temporary file for the mail. */
	tret = cddbd_mktemp();

	if(flags & MF_FAIL) {
		strncpy(buf, errstr, sizeof(buf));
		buf[sizeof(buf) - 1] = '\0';

		if((p = (char *)strchr(buf, '\n')) != NULL)
			*p = '\0';
	}

	/* Return address is currently always the admin. */
	rtn_addr = admin_email;

	switch(eh->eh_class) {
	case EC_COMMAND:
		/* Command response. */
		if(flags & MF_FAIL) {
			cddbd_log(LOG_ERR | LOG_MAIL,
			    "Email command failed: %s", buf);

			cddbd_snprintf(subj_buf, sizeof(subj_buf),
			    cmd_rej_subj, eh->eh_serial);

			sig = gen_rej_sig;
			body = gen_rej_body;
			incl = gen_incl;
			bincl = gen_incl_blank;
			copy_addr = bounce_email;
		}
		else {
			cddbd_snprintf(subj_buf, sizeof(subj_buf),
			    cmd_ok_subj, eh->eh_serial);

			sig = 0;
			body = 0;
			incl = null_incl;
			bincl = null_incl_blank;
			copy_addr = 0;
		}

		subj = subj_buf;

		break;

	case EC_SUBMIT:
		/* We only send mail for rejections and test submissions. */
		if(flags & MF_FAIL) {
			if(flags & MF_TEST) {
				cddbd_log(LOG_ERR | LOG_MAIL,
				    "Test email submission failed: %s", buf);

				subj = test_rej_subj;
			}
			else {
				cddbd_log(LOG_ERR | LOG_MAIL,
				    "Email submission failed: %s", buf);

				subj = sub_rej_subj;
			}

			sig = gen_rej_sig;
			body = sub_rej_body;
			copy_addr = bounce_email;
		}
		else {
			sig = test_ok_sig;
			body = test_ok_body;
			subj = test_ok_subj;
			copy_addr = test_email;
		}

		incl = gen_incl;
		bincl = gen_incl_blank;

		charset = eh->eh_charset;

		break;

	default:
		/*
		subj = gen_rej_subj;
		body = gen_rej_body;
		sig = gen_rej_sig;
		incl = gen_incl;
		bincl = gen_incl_blank;
		copy_addr = bounce_email;

		break;
		*/
		/* Because of the increasing spam problem,
		   we shouldn't be sending people all this
		   mail which responds to spam sent to the
		   freedb submission address.
		*/
		cddbd_freetemp(tret);

		return EE_OK;
	}

	if(eh->eh_flags & EH_ECHO)
		echo = eh->eh_echo;
	else
		echo = 0;

	if((nfp = fopen(tret, "w+")) == NULL) {
		cddbd_log(LOG_ERR | LOG_MAIL,
		    "Can't create mail tmp file %s (%d)", tret, errno);

		return EE_ERROR;
	}

	/* Write out the note string. */
	if(eh->eh_flags & EH_NOTE) {
		if(fprintf(nfp, note, eh->eh_note) == EOF) {
			cddbd_log(LOG_ERR | LOG_MAIL,
			    "Can't write mail tmp file %s (%d)",
			    tret, errno);

			fclose(nfp);
			cddbd_freetemp(tret);

			return EE_ERROR;
		}
	}

	/* Write out the err string. */
	for(i = 0; body && body[i]; i++) {
		if(fprintf(nfp, body[i], errstr) == EOF) {
			cddbd_log(LOG_ERR | LOG_MAIL,
			    "Can't write mail tmp file %s (%d)",
			    tret, errno);

			fclose(nfp);
			cddbd_freetemp(tret);

			return EE_ERROR;
		}
	}

	rewind(fp);

	/* Write out the mail body. */
	while(fgets(buf, sizeof(buf), fp) != NULL) {
		strip_crlf(buf);

		/* remove blank lines, skip nfp write */
		if(is_blank(buf, 0))
			p = bincl;
		else
			p = incl;

		/* zeke - remove the ## comment lines, exit - we are done */
		if(is_DblHash(buf))
			break;

		if(fprintf(nfp, p, buf) == EOF) {
			cddbd_log(LOG_ERR | LOG_MAIL,
			    "Can't write mail tmp file %s (%d)", tret, errno);

			fclose(nfp);
			cddbd_freetemp(tret);

			return EE_ERROR;
		}
	}

	/*!zeke - correct comment follows ???? */
	/* Write out the err string. */
	for(i = 0; sig && sig[i]; i++) {
		if(fprintf(nfp, sig[i], admin_email) == EOF) {
			cddbd_log(LOG_ERR | LOG_MAIL,
			    "Can't write mail tmp file %s (%d)", tret, errno);

			fclose(nfp);
			cddbd_freetemp(tret);

			return EE_ERROR;
		}
	}

	fflush(nfp);

	if(fstat(fileno(nfp), &sbuf))
		len = 0;
	else
		len = sbuf.st_size;

	rewind(nfp);

	/* Figure out if we need to encode the mail. */
	if(!(flags & (MF_ENC | MF_MULTI))) {
		while(fgets(buf, sizeof(buf), nfp) != NULL) {
			if(is_rfc_1521_mappable((unsigned char *)buf, 1, 0)) {
				flags |= MF_ENC;
				break;
			}
		}
	}

	rewind(nfp);

	if(!smtp_open()) {
		fclose(nfp);
		cddbd_freetemp(tret);
		return EE_ERROR;
	}

	if(!smtp_transmit(nfp, charset, subj, eh->eh_rcpt, eh->eh_to,
			  rtn_addr, echo, flags, len, 0)) {
		fclose(nfp);
		cddbd_freetemp(tret);
		return EE_ERROR;
	}

	if(copy_addr != 0 && copy_addr[0] != '\0') {
		rewind(nfp);
		cddbd_snprintf(buf, sizeof(buf), "%s (fwd)", subj);

		if(!smtp_transmit(nfp, charset, buf, copy_addr, copy_addr,
				  rtn_addr, echo, flags, len, 0)) {
			fclose(nfp);
			cddbd_freetemp(tret);
			return EE_ERROR;
		}
	}

	smtp_close();
	fclose(nfp);
	cddbd_freetemp(tret);

	return EE_OK;
}
