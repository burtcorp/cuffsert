# Cuffsert - CloudFormation CLI

The primary goal of cuffsert is to provide a quick "up-arrow-enter" loading of a CloudFormation stack with good feedback, removing the need to click through three pesky screens each time. It figures out whether the stack needs to be created or rolled-back and whether it needs to be deleted first.

Cuffsert allows encoding the metadata and commandline arguments needed to load a template in a versionable file which takes CloudFormation the last mile to really become an infrastructure-as-code platform.

## Usage

Given the file cuffsert.yml:
```yaml
Format: v1
Tags:
  - Name: Role
    Value: webserver
Variants:
  Production:
    Tags:
      - Name: Environment
        Value: production
    Variants:
      Eu1:
        Tags:
          - Name: DC
          - Value: eu1
        Parameters:
          - Name: ElasticIP
            Value: 1.2.3.4
      Us1:
        Tags:
          - Name: DC
            Value: us1
        Parameters:
          - Name: ElasticIP
            Value: 5.6.7.8
```
you can invoke cuffsert like so:
```
cuffsert --metadata=./cuffsert.yml \
  --metadata-path=production-us1 \
  ./nginx.yml
```

If the positional argument is a directory, stack will be read from `stack.yml` (or `.json`) and metadata will be read from `cuffsert.yml` if `--metadata` is not specified.

### Multiple metadata files

If `--metadata` points to a directory (or if no `--metadata` is given and there is a directory `./cuffsert` in the same directory as the stack), all `.yml` files in that directory will be recursively read and each file will be assumed to be at a path matching its path relative to the supplied path. For example, if `./foo/bar.yml` has a variant called `baz` it will match `--metadata-path=foo/bar/baz`. This may be useful if you have very frequent changes to metadata or if you have a lot of variants.

## Metadata file format

The metadata file consists of a hierarchy of configuration sections called "variants". Cuffsert splits the metadata-path by [/-] and starts at the top of the metadata and tries to match the path elements against each  variants sections.

Each level can contain the following keys:

- **StackName**: Stack name used for creating a new stack and finding existing stack to update. If no StackName parameter is found, one will be constructed by joining lowercase variants values and basename of stack file. From the example at the top, stack name will be `production-eu1-nginx`. When stack definition is passed on stdin, StackName must be given in metadata (or on commandline).
- **Tags**: Tags applied at stack level.
- **Parameters**: Provide values for parameters that the stack needs.
- **Variations**: Each sub-key is a possible path element whose value is the hash for the next level.
- **DefaultPath**: You can supply a default selection for a particular path element which is given if none is supplied. Please be advised that having identical names at different hierarchical levels may lead to unexpected results.

Values from deeper levels merged onto values from higher levels to produce a configuration used to create/update the stack.

## Commandline options

    cuffsert [--stack-name=name] [--tag=k:v ...] [--parameter=k:v ...]
      [--metadata=directory | yml-file] [--metadata-path=path/to]
      cloudformation-file | cloudformation-directory

All values set in the metadata file can be overridden on commandline.

`--stack-name=name (-n)` Explicity set the name of the generated stack.

`--tag=key:value (-t)` Override (or set) the value for a specific tag for the template.

`--parameter=key:value (-p)` Override (or set) the value for a specific parameter that is passed on template creation.

`--metadata=file-or-directory (-m)` File or directory to read metadata from. Defaults to `cufsert/` or `cufsert.yml` relative to stack file.

`--metadata-path=path-through-metadata (-P)` Path through variant keys to apply metadata from.

## AWS authentication

cuffsert assumes that the aws client library can authenticate your access via the normal means and makes no particular effort to aid the process, nor does it select revion for you.

## Future work

- Stack policies and policy overrides
- Find and delete resources that block delete or update
