# Neo Crisis Provisioner

This is a small Ansible script to setup environment needed for our awesome Neo Crisis because the world is ending and we have no time to be shelling into servers to do all the hard work manually :)

This provisioner expects the target machine to be a Ubuntu18.04 but does not validates that(feel free to try on different flavors/versions). Stack:

- Python3.6 + virtualenv
- Postgres
- NGINX

## Development

The provided `Vagrantfile` will run the Ansible provisioner when the machine is created having the full project setup.

TLDL:
```
vagrant up
vagrant ssh
cd /vagrant
virtualenv -p python3.6 dev_venv
source dev_venv/bin/activate
pip install -r requirements.txt
python webapp.py
```

The `/vagrant` folder is synced with the host machine so you can edit files on your computer and run on the VM from there.

The `/var/www/neocrisis/` is the "production" code pulled from Github during deployment and served by the web server.

## Helpful commands

```
sudo systemctl daemon-reload
sudo systemctl restart neocrisis_gunicorn
sudo nginx -t
sudo systemctl restart nginx
sudo /var/www/neocrisis/venv/bin/python
```

### To be continued...

Add tags to roles and triggers to restart NGINX, Systemd and neocrisis_gunicorn properly
