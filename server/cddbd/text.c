/*
 * Copyright (C) 2004 Ari Sundholm <megari@freedb.org>
 *
 *     This program is free software; you can redistribute it and/or modify
 *     it under the terms of the GNU General Public License as published by
 *     the Free Software Foundation; either version 2 of the License, or
 *     (at your option) any later version.
 *
 *     This program is distributed in the hope that it will be useful,
 *     but WITHOUT ANY WARRANTY; without even the implied warranty of
 *     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *     GNU General Public License for more details.
 *
 *     You should have received a copy of the GNU General Public License
 *     along with this program; if not, write to the Free Software
 *     Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111, USA.
 *
 */

#include <math.h>
#include <stdlib.h>
#include <string.h>
#include "cddbd.h"
#include "text.h"

INLINE double text_correlate_words(const char *, const char *);
double _text_correlate(const char *, const char *);

/* Produces a logarithm of x to base REWARD. */
INLINE double logrew(double x) {
  return log(x) / log(REWARD);
}

/* Correlate both ways, select the better result */

double text_correlate(const char *s1, const char *s2) {
  double ret1 = 0.0, ret2 = 0.0;
  const char *os1 = s1, *os2 = s2;

  /* Make sure they'll be UTF-8! */
  if(!cond_transcode(&os1, CC_UTF_8) || 
     !cond_transcode(&os2, CC_UTF_8))
    return 0.0;

  ret1 = _text_correlate(os1, os2);
  ret2 = _text_correlate(os2, os1);

  /* Check if a conversion was done. If one was done, the inequalities are true
     and therefore os1 and os2 need to be freed.
  */
  if(os1 != s1) {
    free((void *) os1);
  }
  if(os2 != s2) {
    free((void *) os2);
  }

  if(ret1 > ret2)
    return ret1;
  else
    return ret2;
}

#define corr_score(x, y) x += logrew(y) /* Logarithmic scoring */  /* was (x) *= (y) */

double _text_correlate(const char *s1, const char *s2) {
  char *ts1, *ts2, *p11, *p12, *p21, *p22, *end1, *end2;
  double ret = 0.00; /* Logarithmic scoring */ /* was 1.00; */
  /* The purpose of the following variables is to
     tell the length of the strings without the
     space taken by spaces.
  */
  int len1 = 0, len2 = 0;

  /* We won't alter s1 and s2, but in order to do good
     pointer magic, we need to alter some strings. So
     let's allocate new ones!
     calloc() guarantees that the memory allocated is
     all zeros.

     We should consider if using xrealloc() and then
     memsetting with zero would be better.
  */
  ts1 = (char *) calloc(strlen(s1) + 1, sizeof(char));
  if(!ts1) {
    cddbd_log(LOG_ERR, "Error! Couldn't allocate memory!");
    quit(QUIT_ERR);
  }
  strcpy(ts1, s1);

  ts2 = (char *) calloc(strlen(s2) + 1, sizeof(char));
  if(!ts2) {
    cddbd_log(LOG_ERR, "Error! Couldn't allocate memory!");
    quit(QUIT_ERR);
  }
  strcpy(ts2, s2);

  /* The pointers for the end of ts1 and ts2 */
  end1 = ts1 + strlen(ts1);
  end2 = ts2 + strlen(ts2);

  /* p11 is the start pointer for string 1,
     p12 the end pointer.
  */
  p11 = ts1;
  /* Let's make sure there are no spaces before the first word */
  for(; *p11 == 0x20; p11++); /* Walk consecutive spaces */
  p12 = strchr(p11, 0x20); /* Find ' ' */
  if(p12) /* If a space was found... */
    *p12 = '\0';
  else /* If a space wasn't found... */
    p12 = p11 + strlen(p11);

  len1 = strlen(p11);

  /* p21 is the start pointer for string 2,
     p22 the end pointer.
  */
  p21 = ts2;
  /* Let's make sure there are no spaces before the first word */
  for(; *p21 == 0x20; p21++); /* Walk consecutive spaces */
  p22 = strchr(p21, 0x20); /* Find ' ' */
  if(p22) /* If a space was found... */
    *p22 = '\0';
  else /* If a space wasn't found... */
    p22 = p21 + strlen(p21);

  len2 = strlen(p21);

  while((*p11 != '\0') && (*p21 != '\0') && p11 && p21) {
    /* Generalized this so it'd be easier to change
       the scoring method.
    */
    /* ret *= text_correlate_words(p11, p21); */
    corr_score(ret, text_correlate_words(p11, p21));
    
    if(p12 == end1) break; /* No more correlation can be done */
    p11 = p12 + 1; /* Set the start pointer to the position next to the space */
    for(; *p11 == 0x20; p11++); /* Walk consecutive spaces */
    p12 = strchr(p11, 0x20); /* Find the next space beginning from the start pointer */
    if(p12)
      *p12 = '\0';
    else
      p12 = p11 + strlen(p11);

    len1 += strlen(p11);
    
    if(p22 == end2) break; /* No more correlation can be done */
    p21 = p22 + 1; /* Set the start pointer to the position next to the space */
    for(; *p21 == 0x20; p21++); /* Walk consecutive spaces */
    p22 = strchr(p21, 0x20); /* Find the next space beginning from the start pointer */
    if(p22)
      *p22 = '\0';
    else
      p22 = p21 + strlen(p21);

    len2 += strlen(p21);
    /* printf("About to correlate words \"%s\" and \"%s\"\n", p11, p21);  */
  }

  if(ts1)
    free(ts1);
  if(ts2)
    free(ts2);

  ret /= (double) (len1 > len2 ? len1 : len2);

  return ret;
}

/*
  Correlates between two strings. Here we assume they are words - there
  is a reason for this: long strings with a lot of words are hard to
  correlate between reliably with the method chosen.
*/

INLINE double text_correlate_words(const char *s1, const char *s2) {
  const char *strings[2] = {s1, s2}, *temp;
  int i, val1[2], val2, len1, len2, pos2, temppos;
  double ret = 1.00;

  /*
    1. PREPARATION
    Check strings s1 and s2 for validity. The charset is assumed to be utf8.
    Take down thelengths of the strings and mark pos2 (which denotes the
    position in the utf8 string s2) and temppos (a similar variable
    denoting a position in s2, which is needed for the "rewind" feature
    of the algorithm) as zero.
  */
  
  for(i = 0; i < 2; i++) {
    if(!strings[i]) {
      cddbd_log(LOG_ERR, "text_correlate_words(): Can't correlate: strings[%d] == NULL\n", i);
      return ret;
    }
  }
  
  len1 = utf8strlen(strings[0]);
  len2 = utf8strlen(strings[1]);
  
  pos2 = 0;
  temppos = 0;

  /*
    2. THE MAIN LOOP
    Extract one character from the utf8 string. If it is '\0', the loop ends.
    Check if the extracted character is 0x20 (space) - if it is, the loop
    restarts, effectively skipping the space (NB! There should be NO spaces 
    in the string!).
    If pos2 equals the length of s2, strings[1] is rewound to the position
    denoted by temppos (This is done because, while comparing strings[1] to a
    character, the end of s2 had been encountered and there might be a need
    to rewind) unless the last character of s2 was already compared against a
    character in s1 (in this case, temppos equals pos2 - 1) in which case the
    main loop will be broken out of.
    pos2 is assigned to temppos and temp is
    reused by assigning the current value of strings[0] to it. The next
    character from the utf8 string is assigned to val1[1].
  */
    
  while ((val1[0] = parse_utf8(&strings[0])) > 0) {
    if(val1[0] == 0x20) continue;    

    if(pos2 == len2) { /* all characters in the string have been read */
      if(temppos == pos2 - 1) break; /* Prevent extra comparison */

      temp = s2;
      for(i = 0; i < temppos; i++) {
	/* Hmm... I don't know if it is a good idea to break in
	   case an end-of-string marker or -1 is encountered. On
	   the other hand, they should never be encountered in
	   the first place since we've already gone past this.
	*/
	if(parse_utf8(&temp) < 1) break;
      }
      strings[1] = temp;
      pos2 = i;
    }

    temppos = pos2;

    temp = strings[0];
    val1[1] = parse_utf8(&temp); /* It doesn't matter if it's '\0' or -1 */

    /*
      3. THE CORRELATION LOOP
      Correlation loop starts. Extract one character from strings[1] and make
      sure it isn't '\0' and increment pos2. Check if the extracted character
      is 0x20 (space) - if it is, the loop restarts, effectively skipping the
      space (NB! There should be NO spaces in the string!). Then the two
      extracted characters (val1[0] and val2) are compared. If they match, ret
      is multiplied by REWARD and the correlation loop ends, else val2 is
      further compared against val1[1]. If they match, temp is assigned to
      strings[0] (temp is one character further than strings[0], that's why),
      ret is multiplied by REWARD * PENALTY and the correlation loop ends.
      Else ret is multiplied by PENALTY and the loop continues.
      
      This loop mainly does this: we have the character val1[0] to compare
      against. We try to find a corresponding character val2 from strings[1]
      until strings[1] ends. Each wrong character along the way poses a
      penalty. In addition, the next character in strings[0], val1[1], is
      also compared against each val2. This is because it can very effectively
      address accidentally revesred charatcers and mispellled words (such as
      humiliation as opposed to humaliation) and set the algorithm back on
      track with the words which are correlated by using the rewind feature of
      the algorithm in conjunction.
    */

    /* acidentally revesred charatcers adn mispellled worrds suhc sa humaaliationn vrerssu humiilation
       accidentally reversed characters and misspelled words such as humaliation versus humililiation
    */

    /* Loop until a corresponding character is found or the end of the string
       or an invalid character is encountered.
    */
    for(val2 = parse_utf8(&strings[1]); val2 > 0; val2 = parse_utf8(&strings[1])) {
      pos2++;
      if(val2 == 0x20) continue;

      if(val1[0] == val2) {
	ret *= REWARD;
	break;
      }
      else {
	if(val1[1] != val2) {
	  /* We shouldn't multiply by PENALTY * PENALTY
	     because this comparison is done beforehand.
	  */
	  ret *= PENALTY;
	}
	else {
	  strings[0] = temp;
	  /* Here, however, since the file pointer is
	     moved and two characters effectively
	     compared, we need to multiply accordingly:
	     one didn't match, the other did.
	  */
	  ret *= REWARD * PENALTY; 
	  break;
	}
      }
    }
  }
  
  /*
    4. LENGTH COMPARISON
    Size does matter!
  */
  if(len1 > len2)
    /* ret *= PENALTY * (double) len2 / (double) len1; */
    ret *= pow(PENALTY, len1 - len2);
  else if (len2 > len1)
    /* ret *= PENALTY * (double) len1 / (double) len2; */
    ret *= pow(PENALTY, len2 - len1);

  return ret;
}

/* This WILL free s and form new contents,
   so be sure not to try and use s anywhere
   else!
*/
char *text_reduce(char *s) {
  /* XXX stub */
  return s;
}
