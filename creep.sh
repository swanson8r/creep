#!/usr/bin/sh
#*******************************************************************************
# creep - A shell webcrawler which mimicks a web browser by using telnet to port
#  80. Recursively retreives all webpages under a starting URL. Checks non-html
#  documents and external links for existence. Sadly, <IMG> tags are ignored.
#  See "lynx" for a shell web browser. See "wget" for a more robust webcrawler.
#
# creep: verb: synonym for "crawl". See "web crawler","web spider". 
#         also synonym for "not very efficient".
# creep: noun: synonym for "rude". See "robots.txt", "user agent".
#
# Why use creep? 
#  Find broken links and the pages they occur on.
#  Follow links hidden in <!-- HTML Comments -->
#  Discover any redirected external links.
#  Crawl a site that has $HTTP_REFERER restrictions.
#  Download pages without sitting at a browser,
#   or even having an open terminal session (nohup)
#  Download all pages in website for offline perusal (like wget)
#   (nice for those of us with a dial-up connection).  
#
# Pseudocode - 
#   define functions
#   initialize variables
#   format arguments
#   :start_current_link_loop
#   read link from list
#   format link path
#   check exclusion criteria
#   ping link
#   check link status
#   retreive link
#   glean new links
#   :start_new_link_loop
#   check exclusion criteria
#   format new link
#   check internal vs. external link
#   add new link to list
#   :end_new_link_loop
#   :end_current_link_loop
#   display statistics
#
# FILENAME		DESCRIPTION
# -------		-----------
# ${host}.exc		excludefile: paths to skip
# ${host}.stats		Contains crawler statistics (timestamps)
# ${host}${link}.url	rawlinkfile: List of Raw URLs parsed from ${link}.html 
# ${host}/getme.url	linkfile: List of URLs to retreive, with referring links
# ${host}/external.url	xlinkfile: List of External links to check for existence
# ${host}/bad.url 	badfile: List of URLs and error statuses for a host
# ${host}${link}.HEAD	Telnet output; existence check.
# ${host}${link}.GET	Telnet output; headers + page.
# ${host}${link}.html	HTML only, parsed from ${link}.GET file
# ${host}${link}.bad	Created when a page returns an HTTP status error
#
# Maintenance:
#
# Date		Actor		Action
# -----		------		-------
# 08/28/02	cr33p		Created
# 01/28/03	cr33p		Updated 
#*******************************************************************

#Usage message for invalid command line calls.
if [ $# -lt 1 ] || [ $# -gt 2 ]
then
   usage="\ncreep - a Telnet-based Web Crawler.\n Usage:\n ${0} <hostname> <optional URL>\n"
   echo $usage
   exit 1
fi

######################
#Function Declarations
######################


##############################
#get_timestamp
#Return a formatted date.
##############################
get_timestamp () {
date +%Y%m%d:%H:%M:%S
}


##############################
#to_lower
#convert a string to lowercase
##############################
to_lower () {
if [ $# -ne 1 ]
then
   exit 1
fi
echo "$1" | tr "[:upper:]" "[:lower:]"
}

##############################
#isHttp
#Returns a match if link
# begins with http:// protocol
##############################
isHttp () {
if [ $# -ne 1 ]
then
   exit 1
fi
URL=$1
#A full link begins with the http protocol.
echo "$URL" | grep -E -i -e '^http://'
}

##############################
#notHttp
#Returns a match if link
# begins with valid protocol
# other than http://
##############################
notHttp () {
if [ $# -ne 1 ]
then
   exit 1
fi
URL=$1
echo "$URL" | grep -E -i -e '^mailto:|^ftp:|^news:|^gopher:|^https:|^javascript:'
}

##############################
#isWebpage
#compare file extension 
# to a list of accepted types.
##############################
isWebpage () {
if [ $# -ne 1 ]
then
   exit 1
fi
URL=$1
#Allowed webpages end in: .shtml .shtm .html .htm .cgi .php .asp
#Also allow querystrings and directory browsing.
echo "$URL" | grep -E -i -e '[.](s?html?|cgi|php|asp)[?]?.*$|[/]$'
}

##############################
#isQuery
#Returns a match if link is a
# Querystring.
##############################
isQuery () {
if [ $# -ne 1 ]
then
   exit 1
fi
URL=$1
#A querystring begins with a dot, followed by an extention,
#  followed by a question mark.
echo "$URL" | grep -E -i -e '[.].*[?].*$'
}

##############################
#isAnchor
#Returns a match if link is an
# Anchor Link.
##############################
isAnchor () {
if [ $# -ne 1 ]
then
   exit 1
fi
URL=$1
#An anchor link begins with a hash (if on the same page), or is similar to a querystring.
echo "$URL" | grep -E -i -e '^[#]|[.](s?html?|cgi|php|asp)[#].*$'
}

##############################
#isDir
#Returns a match if link is a
# directory.
##############################
isDir () {
if [ $# -ne 1 ]
then
   exit 1
fi
URL=$1
#A valid directory begins and ends with any number of non-dot characters 
#This can be either a trailing slash, or a filename with no extension.
echo "$URL" | grep -E -i -e '^[^.?]*$'
}

##############################
#isDotDot
#Returns a match if link is
# backing out of a directory.
##############################
isDotDot () {
if [ $# -ne 1 ]
then
   exit 1
fi
URL=$1
echo "$URL" | grep -E -i -e '^[.]{2}'
}

##############################
#add_leading_slash
#add a leading slash to a link
#if one does not already exist
##############################
add_leading_slash () {
if [ $# -ne 1 ]
then
   exit 1
fi
URL=$1
if [ ! "`echo \"${URL}\" | grep -E '^/'`" ]
then
   URL="/${URL}"
fi
echo $URL
}

##############################
#add_trailing_slash
#add a trailing slash to a
# link, if one does not
# already exist
##############################
add_trailing_slash () {
if [ $# -ne 1 ]
then
   exit 1
fi
URL=$1
if [ ! "`echo \"${URL}\" | grep -E '/\$'`" ]
then
   URL="${URL}/"
fi
echo $URL
}

##############################
#remove_trailing_slash
#remove trailing slash from a
# link, if one exists
##############################
remove_trailing_slash () {
if [ $# -ne 1 ]
then
   exit 1
fi
URL=$1
if [ "`echo \"${URL}\" | grep -E '/\$'`" ]
then
   URL=`echo "$URL" | sed -e 's|/$||'`
fi
echo $URL
}

##############################
#remove_leading_slash
#remove leading slash from a
# link, if one exists
##############################
remove_leading_string () {
if [ $# -ne 2 ]
then
   exit 1
fi
URL=$1
string=$2
if [ "`echo \"${URL}\" | grep -E -i -e  \"^${string}\"`" ]
then
   #Make sure that's not all the URL contains
   if [ "`echo \"${URL}\" | grep -E -i -e  \"^${string}\$\"`" ]
   then
      #return a link to the root directory
      URL="/"
   else
      #Find the length of the string, and call cut.
      #Note: to parse with sed on HP-UX 11.0, requires [aA] formatting due to no /I flag.
      #Could call Perl, but not guarenteed to have it on your system.

      string_length=`echo "$string" | wc -c`
      #Do not subtract 1; must start at the next character After the string.

      URL=`echo "$URL"  | cut -c${string_length}-`
   fi
fi
echo $URL
}

############################################################
#telnet_func
#This is the most important function in the script.
#Retreive a webpage. Output is redirected to a file.
#Return status is http status or 1 for error, 0 for success.
############################################################
telnet_func () {

if [ $# -ne 6 ]
then
   exit 1
fi
#Note: there has to be a cleaner way to do this. shift $@ ?
method="$1"
hostname="$2"
port="$3"
link="$4"
reflink="$5"
agent="$6"

#Note: could add a random delay (5 to 30 seconds) to simulate actual browsing.

#Use a "here document" to pass http requests to telnet.
telnet $hostname $port << EOF 2>&1 > ${hostname}${link}.${method}
$method $link HTTP/1.1
Host: $hostname
Referer: $reflink
User-Agent: $agent
Connection: Close

EOF

#Parse the output from telnet.

#Allow return protocols HTTP/1.0 and 1.1
http_status=`grep -i "^HTTP/1" ${hostname}${link}.${method}`

#Set return codes.
#0. 200 OK
#1. Error
#2. Redirected

if [ ! "$http_status" ]
then
   #No status detected. Most likely cause: Hostname Unknown.
   return 1
else
   if [ "`echo \"${http_status}\" | grep '200 '`" ]
   then
      #Status OK
      return 0
   else
      #status was not OK.  Check for redirection.
      if [ "`echo \"${http_status}\" | grep -E -e '^HTTP/1[.][0-1] 3[0-9]{2}'`" ]
      then
         #Redirected.
         return 2
      else
         #Not redirected or OK status. Log as a bad link.
         return 1
      fi
   fi
fi
}

##############################
#depth_gague
#Return the number of
# directories in a URL.
##############################
depth_gague () {
if [ $# -ne 1 ]
then
   exit 1
fi
URL=$1

#Count the number of slashes in the URL.
#Remove all non-slash characters and get the string length.
numdirs=`echo "$URL" | sed 's|[^/]||g' | wc -c`
#account for wc -c counting the newline character 
#Also subtract the leading slash.
numdirs=`expr "$numdirs" - 2`
echo $numdirs
}

##############################
#get_path
#Return the path of a link
##############################
get_path () {
if [ $# -ne 1 ]
then
   exit 1
fi
URL=$1
#Function Call within a Function.
if [ "`isDir $URL`" ]
then
   path=$URL
else
   path=`dirname $URL`
fi
#Ensure that directory link ends in a trailing slash.
path=`add_trailing_slash $path`
echo "$path"
}

##############################
#format_relative_link
#calculate the full link path
# when it begins with ..
#utilizes a cool `cd` trick
##############################
format_relative_link () {
if [ $# -ne 3 ]
then
   exit 1
fi

URL=$1
refering_path=$2
hostdir=$3

#Ensure url needs to be formatted.
#Function Call within a function
if [ ! `isDotDot $URL` ]
then
   exit 1
fi

#`dirname /a/b/c` and `dirname /a/b/c/` both return "/a/b"
#`basename /a/b/c` and `basename /a/b/c/` both return "c"
#A link to a directory either ends in a trailing slash, or in a filename with no extension.

path=`dirname $URL`
file=`basename $URL`

#Function Call within a function
path=`add_trailing_slash $path`

#Function Call within a function
refering_path=`remove_trailing_slash $refering_path`

#Function Call within a function.
path=`add_leading_slash $path`

new_path=${hostdir}${refering_path}${path}

#Function Call within a function.
new_path=`add_leading_slash $new_path`

#We will be using cd to fix the path, so make sure it exists
if [ ! -d ${new_path} ]
then
   mkdir -p ${new_path}
   status=$?
   if [ $status -ne 0 ]
   then
      echo "mkdir ${new_path} failed. Status: $status"
      exit $status
   fi
fi

#This is the fun part... treat the file system path like the URL path
path=`cd ${new_path} > /dev/null; pwd`

#Make sure that the relative link is still within the hostname directory.
test=`echo $path | grep -E "^${hostdir}"`
#Note: if passing in a starting URL, hostdir should be the directory for the link.
if [ ! "$test" ] 
then
   #path backed out too far. Repairing...
   path=$hostdir
fi
#Strip off the hostdir; 
path=`echo $path | sed -e "s|^${hostdir}||"`
#return a telnet-friendly link
echo "${path}/${file}"
}

################################################################################
#                                    Main
################################################################################

#Limit the number of directories below the starting url to retreive.
max_depth=3

#Make this crawler look like Internet Explorer 5.0 (see "creep" as a noun)
#Note: add Netscape, Opera, and other favorites.
agent="Mozilla/4.0 (compatible; MSIE 5.0; Windows 95; DigExt)"

#telnet port to connect to.
#override for special intranets.
#Note: should check links for hostname:port
port=80

#################
#Format Arguments 
#################

#Ensure case of hostname 
host=`to_lower "$1"`
#Note: Should check HTTP domain name formatting: host.server.tld

host=`remove_trailing_slash $host`

#Strip off http:// in hostname.
if [ "`isHttp $host`" ]
then
   host=`echo "$host" | sed -e 's|^http://||'`
fi

#If optional URL is blank, start at the root
link=$2	
if [ "$link" = "" ]
then
   echo "No Starting URL given. Using root directory."
   link="/"
fi

#Set the directory on Unix to store the retreived webpages.
hostdir="`pwd`/${host}"

#Filename containing list links to retreive.
linkfile="${host}/getme.url"
excludefile="${host}.exc"
xlinkfile="${host}/external.url"
badfile="${host}/bad.url"
statsfile="${host}.stats"

#take snapshots of the timestamp during the process
start_time=`get_timestamp`
echo << EOF > $statsfile
############################
# Creep statistics for $host
############################
EOF

echo "Started:		$start_time" | tee -a $statsfile

#Check if this hostname has been validated before.
if [ ! -d ${host} ]
then
   #Note: could add prompt to exit
   echo "New host: ${host}"

   #Note: mkdir could fail. check return status
   mkdir ${host}
   status=$?
   if [ $status -ne 0 ]
   then
      echo "mkdir ${host} failed. Status: $status"
      exit $status
   fi
   #Set the starting link
   echo "$link	http://${host}/" > $linkfile
else
   echo "Continuing crawl of ${host}"
fi

########################
#Begin Current Link Loop
########################

while read LINKDATA
do
   #Check for Link and Referer.
   if [ ! "`echo \"$LINKDATA\" | grep -E '.	.'`" ]
   then
      echo "Error: Missing Link or Referer: |${LINKDATA}|"
      echo " "
      #Skip this link and try the next one.
      continue
   fi

   ####################
   #Read Link From List
   ####################

   #Parse out the referring URL.
   link=`echo "$LINKDATA" | cut -f1`
   reflink=`echo "$LINKDATA" | cut -f2`
   
   #################
   #Format Link Path
   #################

   #Fully qualify the current link for logging as a referer.
   #(link is stored with leading slash.)
   next_reflink="http://${host}${link}"

   #Set the filename to store list of raw links for this page
   rawlinkfile="${host}${link}.url"

   #Get the path of this link.
   link_path=`get_path $link`

   #Display the formatted link.
   echo "Checking Link ${link}"

   #########################
   #Check Exclusion Criteria
   #########################

   #Check if link is deeper than maximum limit
   link_depth=`depth_gague "$NEXTLINK"`
   #echo "Depth: $link_depth"
   if [ $link_depth -gt $max_depth ]
   then
      echo "	Skipping (Link Too Deep)"
      echo " "
      continue
   fi

   #Check filetype of linked document.
   if [ ! "`isWebpage $link`" ]
   then
      #Non-html document. Check for existence.
      if [ -f "${host}${link}.HEAD" ]
      then
   	echo "$link has already been pinged"
        echo " "
   	continue
      fi
   else
      if [ -f "${host}${link}.html" ]
      then
   	echo "$link has already been retreived"
        echo " "
   	continue
      elif [ -f "${host}${link}.bad" ]
      then
   	echo "$link has already been attempted (bad link)"
        echo " "
   	continue
      fi
   fi

   #Check exclusion list
   if [ -f "$excludefile" ]
   then
      #Look for the exclude path in the link path.
      #Match if link path begins with excludepath.
      match=`grep -i "^${link_path}" $excludefile`
      if [ "$match" ]
      then
         echo "Excluding $link ($match)"
         echo " "
         continue
      fi
   fi

   ##########
   #Ping Link
   ##########

   #Create subdirectory so that the webpage can be downloaded.
   if [ ! -d "${host}${link_path}" ]
   then
      echo "Creating link path: ${host}${link_path}"
      #Use -p flag to force creation of intermediate directories.
      mkdir -p ${host}${link_path}
      status=$?
      if [ $status -ne 0 ]
      then
         echo "Error creating directory ${host}${link_path} : Status $status"
         exit $status
      fi
   fi

   echo "Pinging ${host}${link}"
   telnet_func HEAD ${host} ${port} ${link} ${reflink} "${agent}"
   status=$?

   ##################
   #Check link status
   ##################

   #Check the return status from telnet.
   if [ $status -ne 0 ]
   then
      if [ $status -eq 1 ]
      then
         echo "Error: $status	${host}${link}	${reflink}" | tee -a $badfile
         echo "" 
         #create a .bad file so we don't attempt to retreive this page again.
         touch ${host}${link}.bad
         continue
      else
         echo "Page is Redirected; New Location"
         #create a .html file so this page is not checked again.
         touch "${host}${link}.html"

         #Strip off the HTTP header.
         location=`grep -E -i -e '^Location: ' ${host}${link}.${method} | sed 's|^Location: ||'` 

         #Add the new link to the list of raw URLs to process.
         echo $location | tee -a $rawlinkfile
         #Note: Dolphin

         continue
      fi
   else
      #Status is OK.
      #Check for filetype.
      if  [ ! "`isWebpage $link`" ]
      then
         #Only get webpages.
         #Note: Does this include directory browsing?
         echo "Not a Webpage. Skipping."
         echo " "
         continue
      fi

      ##############
      #Retreive Link
      ##############

      echo "Getting ${host}${link}"
      telnet_func GET ${host} ${port} ${link} ${reflink} "${agent}"
      status=$?

      #Check the return status from telnet.
      if [ $status -ne 0 ]
      then
          echo "Error: $status	${host}${link}	${reflink}" | tee -a $badfile
          echo ""
          continue       
      fi
      link_time=`get_timestamp`
      echo "Link Retreived		$link_time	$link" | tee -a $statsfile

      ################
      #Glean New Links
      ################

      #Remove the telnet headers, leaving only the HTML.
      #Note: Since sed cannot match over newlines, should try a different approach.

      #The HTTP headers end with a blank line.
      http_header_start=`grep -E -n '^$' ${host}${link}.GET | head -1 | cut -f1 -d ':'`
      http_header_start=`expr "$http_header_start" + 1`

      #tail -n + means "start at the top of the document"
      #Note: If not retreiving javascript links, can remove <SCRIPT> tag data
      tail -n +${http_header_start} ${host}${link}.GET > ${host}${link}.html

      #We have the .HEAD document, so we can delete the .GET file
      rm ${host}${link}.GET

      #We now have a local copy of the webpage.

      #Parse links out of the HTML document. Pipe to sed for cleanup
      #A webpage link looks like <A HREF, <AREA (image map), or <FRAME SRC.

      #Note: Should look for "<IMG SRC=" tags.
      grep_link_pattern='<[ 	]*A(REA)?[ 	]+[^>]*HREF[ 	]*=[ 	]*["'\'']?[^"'\''>]*['\'']?[^>]*>'
      grep_frame_pattern='<[ 	]*FRAME[ 	]+[^>]*SRC[ 	]*=[ 	]*["'\'']?[^"'\''>]*["'\'']?[^>]*>'

      sed_link_pattern='^.*<[ 	]*[aA].*[ 	]*[^>]*[hH][rR][eE][fF][ 	]*=[ 	]*["'\'']*\([^"'\''> 	]*\)["'\'']*[^>]*>.*$'

      sed_frame_pattern='^.*<[ 	]*[fF][rR][aA][mM][eE][ 	]*[^>]*[sS][rR][cC][ 	]*=[ 	]*["'\'']*\([^">'\'' 	]*\)["'\'']*[^>]*>.*$'

      grep -E -i -e "${grep_link_pattern}" -e "${grep_frame_pattern}" ${host}${link}.html > ${host}${link}.grep

      status=$?
      if [ $status -eq 2 ]
      then
         echo "Error: Link Parsing (grep). Status: $status"
         exit $status
      fi

      cat ${host}${link}.grep | sed -e "s|${sed_link_pattern}|\1|" -e "s|${sed_frame_pattern}|\1|" > $rawlinkfile
      status=$?
      if [ $status -ne 0 ]
      then
         echo "Error: Link Parsing (sed). Status: $status"
         exit $status
      fi
      rm ${host}${link}.grep
   fi
   echo "Raw URL list:"
   cat $rawlinkfile | more
   echo " "

   ####################
   #Begin New Link Loop
   ####################

   #Iterate over the list of links in the webpage.
   while read NEXTLINK
   do
      echo "Processing raw link: $NEXTLINK"

      #########################
      #Check Exclusion Criteria
      #########################

      if [ "$NEXTLINK" = "" ]
      then
         echo "Discarding empty link"
         continue
      fi
 
      if [ "`echo $NEXTLINK | grep -E -i -e '^http://$'`" ]
      then
         echo "Discarding Bare http:// link"
         continue
      fi

      if [ "`echo "$NEXTLINK" | grep -E -i \"^${host}\$\"`" ]
      then
         echo "Skipping (link = host)"
         continue
      fi
 
      if [ "`notHttp $NEXTLINK`" ]
      then
         echo "Discarding (non-http method)"
         continue	
      fi

      if [ "`isAnchor $NEXTLINK`" ]
      then
         #Note: Could follow the anchor link
         echo "Discarding (Anchor Link)"
         continue	
      fi

      ################
      #Format New Link
      ################

      #Check for directory browsing.
      if [ "`isDir $NEXTLINK`" ]
      then
         echo "Directory"
         nextlink_path=`add_trailing_slash $NEXTLINK`
      elif [ "`isQuery $NEXTLINK`" ]
      then
         echo "Query"
         #Separate querystring from link.
         #Note: what about cut -c"?" ?
         nextlink_bare=`echo "$NEXTLINK" | sed -e 's|\(^.*[.].*\)[?].*$|\1|'`
         nextlink_querystring=`echo "$NEXTLINK" | sed -e 's|^.*[.].*\([?].*$\)|\1|'`

         #Replace / in querystring with HTML entity to avoid unwanted Unix directory creation.
         nextlink_querystring=`echo "$nextlink_querystring" | sed -e 's|/|\&#47\;|g'`
        
         #Do Browser-style encoding of HTML entities.
         #Note: should do this for all entities
         nextlink_querystring=`echo "$nextlink_querystring" | sed -e 's|\&[aA][mM][pP]\;|\&|g'` 

         #Re-join the querystring to the link.
         NEXTLINK="${nextlink_bare}${nextlink_querystring}"

         #Glean out the path information from the URL
         nextlink_path=`dirname $nextlink_bare`
      else
         echo "File"
         nextlink_path=`dirname $NEXTLINK`
      fi

      #DEBUG do we actually use this formatted path?
      nextlink_path=`add_trailing_slash $nextlink_path`

      #Require fully-qualified links	
      if [ ! "`isHttp $NEXTLINK`" ]
      then
         echo "	Relative URL"

         ###################
         #Fix Relative Links
         ###################

         #Three potential relative links.
         #1. leading ..
         #2. leading bare filename
         #3. leading slash

         #Check if we are backing out of this directory.
         if [ "`isDotDot $NEXTLINK`" ]
         then
            #Case 1.
            #New path needs to be determined based on current path.
            NEXTLINK=`format_relative_link $NEXTLINK $link_path $hostdir`
         elif [ ! "`echo $NEXTLINK | grep -E '^/'`" ]
         then
            #Case 2.
            #Link is relative to current path. Append.
            NEXTLINK="${link_path}${NEXTLINK}"
         fi
         #(else, Case 3. Link is already properly formatted.) 

      #Tack on hostname for comparison to external links.
      NEXTLINK="http://${host}${NEXTLINK}"
      #Link is now formatted.
      else
         echo "	Fully qualified URL"
      fi

      #####################
      #Add New Link to List
      #####################

      if [ "`echo $NEXTLINK | grep -E -i -e \"^http://${host}\"`" ]
      then
         echo "		Internal URL"
         #Translate into a telnet-compatable link
         NEXTLINK=`remove_leading_string $NEXTLINK "http://${host}"`
         echo "			Storing as $NEXTLINK"
         echo "$NEXTLINK	$next_reflink" >> $linkfile
      else
         echo "		External URL"

         echo "			Storing as $NEXTLINK"
         echo "$NEXTLINK	$next_reflink" >> "$xlinkfile"
      fi

   ##################
   #End New Link Loop
   ##################

   done < $rawlinkfile
   echo ""

#Read the next link to visit.

######################
#End Current Link Loop
######################

done < $linkfile

#Note: could wrap the above into a function.
#########################
#Begin External Link Loop
#########################

echo "Done."

#Note: calculate elapsed time.
#Counts & percents of visited, bad, redirected links
#Avg time per link

###################
#Display Statistics
###################

end_time=`get_timestamp`
echo "Finished:		$end_time" | tee -a $statsfile
cat $statsfile | more