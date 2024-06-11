# Moving to a Zero Trust architecture in AWS using Infrastructure-as-Code

In this repository, you will leverage [AWS Verified Access]() and [Amazon VPC Lattice]() to simplify the connectivity between services, while improving the security posture of the communication. The Infrastructure-as-Code framework used is **Terraform**.

This example requires the use of 3 AWS Accounts: one for the central Networking resources; one for the frontend application (hosted using [Amazon ECS Fargate]()), and another one for the backend applications (hosted using Fargate and [AWS Lambda]()). The following resources are created:

**Networking Account**

* Amazon VPC Lattice service network, which is shared with the AWS Organization using [AWS RAM]().
* [Amazon Route 53 Profile]() with a [Private Hosted Zone]() associated. 
    * The Profile is shared using AWS RAM.
    * The Private Hosted Zone contains the corresponding CNAME records translating the VPC Lattice services' custom domain names to the VPC Lattice generated domain names.
* [AWS Systems Manager Parameter Store](https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-parameter-store.html) is used to share information between AWS Accounts - Route 53 Profile ID and VPC Lattice service network ARN.

**Frontend Account**

* Amazon VPC hosting a [Amazon ECS Fargate]() cluster for the *frontend application*. The Fargate service is the target of an [Application Load Balancer]()
    * VPC is associated to the VPC Lattice service network shared by the Networking AWS Account.
* [Amazon ECR]() repository to store the *frontend application* code.
* [AWS Verified Access]() resources to access the *frontend application* VPN-less with user authentication and authorization. The use of [AWS Identity Center]() is expected, but not created in this repository.

**Backend Account**

* Amazon VPC hosting a [Amazon ECS Fargate]() cluster for the *mservice1 application*. The Fargate service is the target of an [Application Load Balancer]()
    * VPC is associated to the VPC Lattice service network shared by the Networking AWS Account.
* [Amazon ECR]() repository to store the *mservice1 application* code.
* [AWS Lambda]() function containing *mservice2 application*.
* [VPC Lattice services]() for *mservice1* and *mservice2* applications. Both services are associated to the VPC Lattice service network associated by the Networking AWS Account.

## Pre-requisites

* When using several AWS Accounts, make sure you use different AWS credentials when initializing the provider in each folder.
* This repository does not configure AWS Identity Center. Check the [documentation]() to understand how to enable it in your AWS Accounts (if not done already).
* Terraform installed.

## Code Principles

* Writing DRY (Do No Repeat Yourself) code using a modular design pattern.

## Usage

* Clone the repository

```
git clone https://github.com/aws-samples/moving-to-a-zero-trust-architecture-in-aws
```

Edit the *variables.tf* file in each folder to configure the environment (AWS Region to use must be the same in all AWS Accounts):

* Networking AWS Account:
    * AWS Region to use.
    * Public Hosted Zone ID (for AWS Verified Access endpoint resolution)
    * Private Hosted Zone name (for Amazon VPC Lattice services' resolution)
    * *Frontend* and *backend* AWS Account IDs.
    * *Frontend*, *mservice1* and *mservice2* domain names.
* Frontend AWS Account:
    * AWS Region to use
    * [Amazon Certificate Manager]() certificate ARN (for HTTPS in Verified Access endpoint).
    * *Frontend* application domain name.
    * Networking AWS Account ID.
    * Identity Center Group ID.
* Backend AWS Account:
    * AWS Region to use
    * Amazon Certificate Manager certificate ARN (for HTTPS in VPC Lattice services).
    * *mservice1* and *mservice2* application domain names.
    * Networking AWS Account ID.
    * IAM Role ARN used for the *frontend* application. This is used in VPC Lattice auth policies.
* To share parameters between AWS Accounts, you will need to provide the Account ID of the corresponding Account in each folder. 
* We recommend the use of tha *tfvars* file to provide the required parameters.

## Deployment

* **Step 1**: Networking Account resources

```
cd network/
terraform apply
```

* **Step 2**: Frontend Account resources

```
cd frontend/
terraform apply
```

* **Step 3**: Deploying *frontend* application
    * Move to /applications/portal and change the following files:
        * In `dockerpush.sh`, provide AWS Region used and the AWS Account ID for the *frontend* application in lines 3, 5, and 6.
        * In `index.py`, provide *mservice1* domain name in lines 24 and 25. Also add the AWS Region used in lines 27 and 32.
    * Build and push the code to the ECR repository created in Step 2.


```
cd applications/portal/
./dockerpush.sh
```

* **Step 4**: Backend Account resources

```
cd backend/
terraform apply
```

* **Step 5**: Deploying *mservice1* application
    * Move to /applications/mservice1 and change the following files:
        * In `dockerpush.sh`, provide AWS Region used and the AWS Account ID for the *frontend* application in lines 3, 5, and 6.
        * In `app1.py`, provide *mservice2* domain name in lines 17 and 18. Also add the AWS Region used in line 24.
    * Build and push the code to the ECR repository created in Step 4.


```
cd applications/mservice1/
./dockerpush.sh
```

## Security

See [CONTRIBUTING](CONTRIBUTING.md#security-issue-notifications) for more information.

## License

This library is licensed under the MIT-0 License. See the LICENSE file.