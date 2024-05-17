# Deps Relay

A simple
mobile [Hosted Pub Repository Specification Version 2](https://github.com/dart-lang/pub/blob/master/doc/repository-spec-v2.md)
relay/cache server that supports local / hosted and git upstreams.

```bash
# start the relay server
git clone https://github.com/mikklfr/deps_relay
cd deps_relay
docker-compose up -d

# fetch the packages using the relay server
PUB_HOSTED_URL=http://127.0.0.1:8080/flutter flutter pub get
```

-----

## Purpose

This server allows you to create a pub server that can cache and serve the package artifacts you use in your mobile projects.

Because it's using upstreams, you don't have to manually copy them. Caching is done on the fly for you and whenever an artifact becomes absent, the cached version will be served. 

## Features

- [x] On the fly local cache copy of artifacts (using S3 Compatible backend)
- [x] Hosted Pub Repository upstreams
- [x] Git repositories as upstreams (based on branch / tags)
- [x] Token based authentication (and optional package query filtering based on regex)

## Getting Started

Create your configuration file using the ``configuration.json`` file located in the ``conf`` folder and run the server.

### Docker Compose

You can also use Docker and docker-compose to run the server using the embedded ``docker-compose.yml`` file.

### Manual Compilation and Run

```bash
dart pub get
dart run build_runner build --delete-conflicting-outputs
dart compile exe bin/server.dart -o deps_relay
chmod +x deps_relay
./deps_relay --conf <path_to_your_config_file>
```

## I have an issue
- [x] Double check your configuration file and disabled unused features
  - Ensure that the base URL is correct and accessible from the client side
- [x] Check that the S3 backend is correctly configured
- [x] Check that the Git repositories are accessible
  - [x] If you use SSH, check that the SSH keys are accessible.
  - [x] If you use HTTPS, check that the repository is public or that you have the correct credentials in the URL or that your git keychain is correctly configured.
- [x] If you use authentication, check that the token is set on the client side. (``dart pub token add "http://yoursite.com[:port]/flutter"``). **Do not forget the ``/flutter``**

## Configuration

Details about the configuration file fields

### server

This is a common base configuration object for the server.

- **baseUrl** : This should reflect your IP or domain name as it will be used to generate the public links of your
  artefacts.
- **port** : The port the server will listen to

### flutter

Flutter pub server specific configuration.

- **enableDebugRoutes** : Enable debug routes, dangerous, only use for debugging.
- **requiresAuthentication** : Enable the authentication features, see below the ``users`` field for more details
- **storePackages** : Create a local cache of the packages when serving the upstreams versions
- **useLocalPackages** : Use the local cache of the packages as a data source
- **useHostedUpstreamPackages** : Use the Pub Hosted upstreams as data sources, see below the ``hostedUpstreams`` field
  for more details
- **useGitPackages** : Use the Git repositories as data sources, see below the ``gitUpstreams`` field for more details

#### database

The application uses Isar as a database. The database will be stored in a folder. The folder will be created automatically by the application. You may persist the database folder to keep the data between restarts.

- **path** : Location of to the database folder

#### storage

The application uses S3 Compatible backend to store the packages artifacts.

- **s3Bucket** : The S3 compatible bucket name
- **s3Region** : The S3 compatible region
- **s3Endpoint** : The S3 compatible endpoint
- **s3AccessKey** : The S3 compatible access key
- **s3SecretKey** : The S3 compatible secret key

#### hostedUpstreams

If you want to chain your request to pub hosted repository, you can define the hosted upstreams here.

- **url** : The URL of the hosted Pub Repository

#### gitUpstreams

The Git Upstream feature will try to create a compatible hosted package on the fly. The version you'll have to use in Flutter will be following the default versioning convention. ``1.0.0``, ``1.0.0+1``, ``1.0.0-dev.1`` and so on.
If your branch or tag is not following the convention, the server will try to create a compatible version. For instance ``release/lib_1.0.0_test`` will be transformed to ``1.0.0``. and ``release/lib_1.0.0-test`` will be transformed to ``1.0.0-test``.

- **name** : Name of the flutter package. Does not need to match the actual package name from the repository
- **url** : The URL of the Git repository. Https (easier) or SSH.
- **subPath** : **Optional**  Subpath to the pubspec.yaml
- **sshHost** : **Optional**  Only required for SSH repositories. Define the domain name of the SSH server. Exemple:
  github.com

#### users

A basic but simple authentication system based on Authorization Bearer headers.

- **name** : internal name for you to identify the user
- **token** : any secret you will use to authenticate the user. Needs to be added on client side with ``dart pub token add "http://yoursite.com[:port]/flutter"``. **Do not forget the ``/flutter``**
- **regex** : **Optional**  A regex to filter the packages the user can access. If not defined, the user will have
  access to all packages.