<h1>WCG_bash</h1>

WCG_bash is a bash script that uses the World Community Grid API to download workunit data and reprocess that data from
JSON to CSV and then load the data into a MySQL database. This script presumes the existence of a running instance of MySQL but provides a function to correctly create the table to accomodate the WCG schema. 

<b>Important:</b> It also requires that you set up your MySQL client with the MySQL Config Editor to allow encrypted passwordless access.  Lastly, you will need to create a script called wcg_env.sh with your WCG "member name" and WCG "Verfication Code" which can both be found on your WCG profile page.

<h2>Function descriptions</h2>

<h3>get_results_count</h3>

This is a single call to the API that retrieves the number of workunits to download.  It is not currently in use but was made available for future ideas.

<h3>retrieve_full_data</h3>

This uses 'curl' to retrieve all available work units by using an undocumented feature of the WCG API by setting the limit
to zero.  The API documentation specifies using 'limit' and 'offset'. I have a version that works with limit and offset as well but it is not provided here. If you ask in a comment, I'll upload it.

<h3>parse</h3>

This function uses string manipulation in the shell (not a bashism - this should work in any shell) to parse key/value pairs assigning only the values to a variable called 'value'. The construct is <code>${var#*SubStr}</code> where the beginning of the string up to the substring will be dropped.  In the specific case from the code <code>value="${line#\*:}"</code> the variable $line contains the key/value pair from the JSON separated by ':'  The key (the substring) up to and including the delimiter (':') are dropped leaving the value to be assigned to the variable $value.

<h3>create_load</h3>

The main purpose of this function is to rewrite the JSON data from the API into CSV format. <code>create_load</create_load> does most of the heavy lifting by reading all output lines from the API after calling other functions to remove JSON formatting and adding sql commands to create a sql load script. There are 19 fields per record.  

This function syncronizes the order of the fields adding a placeholder for the one that gets added dynamically based on workunit status.  But mostly it coverts newlines to commas and inserts parentheses and newlines around each record. By omitting the function calls to <code>create_insert</code> and <code>create_update</code> you can simply derive a plain csv file.

<h3>de_json</h3>

De_json uses an 'ex' editor script/heredoc to strip out JSON formatting such as curly braces and extraneous commas.

<h3>tidy</h3>

The tidy function performs two tasks - 1) it swaps the order of ,) to ), to correctly separate each SQL command and removes
the last line which contains an extraneous ) in the "values" created by the create_load function.






