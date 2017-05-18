
rm $0
'rdmd' '-debug' 'app.d'
exit_code=$?
echo "
-----------------------
(program returned exit code: $exit_code)"
echo "Press return to continue..."
dummy_var=""
read dummy_var
exit $exit_code
