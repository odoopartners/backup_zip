# get deployments
kubectl get deployment -n odoo -o=name | grep odoo1 | sed "s/^.\{16\}//" |\


while read deploy; \
 do
   echo "#############"
   echo "$deploy "
   echo "#############"


   if [[ $deploy == *"test"* ]]; 
   then
       echo "Test deploy will not be uploaded"
   else
       # Get new pod
       kubectl get pods -n odoo -o=name --field-selector=status.phase=Running | grep $deploy | sed "s/^.\{4\}//" |\
       while read pod; \
        do
          echo "* $pod"
          echo "- Copyng executing script..."
          kubectl cp ./backups/generate_backups.py odoo/$pod:/opt/odoo_dir/odoo
          kubectl cp ./backups/odoo-backup.sh odoo/$pod:/opt/odoo_dir/odoo
          echo "- Executing script..."
          kubectl exec -n odoo -t $pod -- bash -c "cd /opt/odoo_dir/odoo && python generate_backups.py localhost:8069 $deploy"
		  error=$?
		  if [ $error -eq 0 ]; then echo "OK"; else echo "ERROR: $error"; fi

       done
   fi

done	

