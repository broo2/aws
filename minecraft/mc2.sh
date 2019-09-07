
# install requirements for minetcaft server
yum update
yum install java-1.8.0-openjdk-headless.x86_64 GroupDescription

# create ./minecraft home folder and download latest server
mkdir ./minecraft
cd ./minecraft
wget https://launcher.mojang.com/v1/objects/3dc3d84a581f14691199cf6831b71ed12$
chmod +x server.jar

# automatically accept minecraft EULA
echo "eula=true" > ./eula.txt

# run minecraft server
java -Xmx1024M -Xms1024M -jar server.jar nogui
