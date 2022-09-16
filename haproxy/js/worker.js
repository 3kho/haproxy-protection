async function hash(data, method) {
	const buffer = new TextEncoder('utf-8').encode(data);
	const hashBuffer = await crypto.subtle.digest(method, buffer)
	return Array.from(new Uint8Array(hashBuffer));
}

onmessage = async function(e) {
	const [challenge, id, threads] = e.data;
	console.log('Worker thread', id,'got challenge', challenge);
	let i = id;
	let challengeIndex = parseInt(challenge[0], 16);
	while(true) {
		let result = await hash(challenge+i, 'sha-256');
		if(result[challengeIndex] === 0x00
			&& result[challengeIndex+1] === 0x41){
			console.log('Worker thread found solution:', i);
			postMessage([id, i]);
			break;
		}
		i+=threads;
	}
}
