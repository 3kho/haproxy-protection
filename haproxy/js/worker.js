async function hash(data, method) {
	const buffer = new TextEncoder('utf-8').encode(data);
	const hashBuffer = await crypto.subtle.digest(method, buffer)
	return Array.from(new Uint8Array(hashBuffer));
}

onmessage = async function(e) {
	const [challenge, difficulty, id, threads] = e.data;
	console.log('Worker thread', id,'got challenge', challenge, 'with difficulty', difficulty);
	let i = id;
	let challengeIndex = parseInt(challenge[0], 16);
	while(true) {
		let result = await hash(challenge+i, 'sha-1');
		let middle = true;
		for(let imiddle = 1; imiddle <= difficulty; imiddle++) {
			middle = (middle && (result[challengeIndex+imiddle] === 0x00));
		}
		if(result[challengeIndex] === 0xb0
			&& middle === true
			&& result[challengeIndex+difficulty+1] === 0x0b){
			console.log('Worker thread found solution:', i);
			postMessage([id, i]);
			break;
		}
		i+=threads;
	}
}
