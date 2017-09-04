<?php
// Returns a list of all custom FTP users
// Only custom users are setup when tying into the EHCP FTP API
$countNotNull = 0;
$users_list = "";
$success = 0;
$errorCount = 0;

if (isset($errors)) {
    unset($errors);
}

if (!isset($connection)) {
    include "config.php";
}

include_once 'db_functions.php';

if (!isset($connection)) {
    die("Problem setting up connection!");
} else {
    $SQL = "SELECT ftpusername, homedir, domainname, status FROM ftpaccounts";
    $Result = execSQL($SQL, $connection);
    
    if ($Result !== FALSE) {
		$count = countSQLResult($Result);
        
        if ($count > 0) {

			while ($row = getSQLRow($Result)) {

				// Only show custom entries... do not allow to modify EHCP accounts.
				// domainname field will be NULL for custom FTP entries
					
				if (!empty($row['homedir']) && (empty($row['domainname']) || $row['domainname'] === NULL) && (empty($row['status']) || $row['status'] === NULL)) {
					$countNotNull++;
					$username = $row['ftpusername'];
					$dir = $row['homedir'];
					$users_list.= $username . "\t" . $dir . "/./\n";
				}
			}
            
            if ($countNotNull == 0) {
                $errorCount++;
                $errors[] = "There are no custom FTP accounts yet in the EHCP database!";
            }
        } else {
            $errorCount++;
            $errors[] = "No FTP accounts exist from the ftpaccounts table!";
        }
    } else {
        $errorCount++;
        $errors[] = getSQLError($connection);
		$success = 0;
    }

    // Log errors
    
    if ($errorCount > 0) {
        addToLog($errors);
    }
}

// Return the user list
echo $users_list;
?>
